#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

GIT_CONFIG="$TEST_ROOT/gitconfig"
REMOTE="$TEST_ROOT/remote.git"
WORK="$TEST_ROOT/work"

chezmoi execute-template --source="$REPO_ROOT" \
    --override-data '{"machine_profile":"devcontainer","features":{"use_1password":false}}' \
    <"$REPO_ROOT/home/dot_config/git/config.tmpl" >"$GIT_CONFIG"

export GIT_CONFIG_GLOBAL="$GIT_CONFIG"
export GIT_CONFIG_NOSYSTEM=1

git init --bare --initial-branch=main "$REMOTE" >/dev/null
git init --initial-branch=main "$WORK" >/dev/null
git -C "$WORK" config user.name "Sweep Test"
git -C "$WORK" config user.email "sweep@example.invalid"
git -C "$WORK" config commit.gpgsign false
git -C "$WORK" remote add origin "$REMOTE"

printf 'base\n' >"$WORK/base.txt"
git -C "$WORK" add base.txt
git -C "$WORK" commit -m base >/dev/null
git -C "$WORK" push -u origin main >/dev/null

git -C "$WORK" switch -c merged-gone >/dev/null
printf 'merged\n' >"$WORK/merged.txt"
git -C "$WORK" add merged.txt
git -C "$WORK" commit -m merged >/dev/null
git -C "$WORK" push -u origin merged-gone >/dev/null
git -C "$WORK" switch main >/dev/null
git -C "$WORK" merge --ff-only merged-gone >/dev/null
git -C "$WORK" push origin main >/dev/null
git -C "$WORK" push origin --delete merged-gone >/dev/null

git -C "$WORK" switch -c unmerged-gone >/dev/null
printf 'unmerged\n' >"$WORK/unmerged.txt"
git -C "$WORK" add unmerged.txt
git -C "$WORK" commit -m unmerged >/dev/null
git -C "$WORK" push -u origin unmerged-gone >/dev/null
git -C "$WORK" switch main >/dev/null
git -C "$WORK" push origin --delete unmerged-gone >/dev/null
git -C "$WORK" fetch --prune >/dev/null

EXPECTED_BRANCHES=$'merged-gone\nunmerged-gone'
[ "$(git -C "$WORK" sweep | LC_ALL=C sort)" = "$EXPECTED_BRANCHES" ]
git -C "$WORK" show-ref --verify --quiet refs/heads/merged-gone
git -C "$WORK" show-ref --verify --quiet refs/heads/unmerged-gone

if git -C "$WORK" sweep-delete >/dev/null 2>&1; then
    echo "git sweep-delete removed an unmerged branch" >&2
    exit 1
fi
if git -C "$WORK" show-ref --verify --quiet refs/heads/merged-gone; then
    echo "git sweep-delete did not remove the merged branch" >&2
    exit 1
fi
git -C "$WORK" show-ref --verify --quiet refs/heads/unmerged-gone

[ "$(git -C "$WORK" sweep)" = "unmerged-gone" ]
git -C "$WORK" sweep-force >/dev/null
if git -C "$WORK" show-ref --verify --quiet refs/heads/unmerged-gone; then
    echo "git sweep-force did not remove the explicitly selected branch" >&2
    exit 1
fi
[ -z "$(git -C "$WORK" sweep)" ]
git -C "$WORK" sweep-delete
git -C "$WORK" sweep-force

# A gone current branch remains observable, but Git must reject both deletion
# modes with a visible error and a non-zero status.
git -C "$WORK" switch -c current-gone >/dev/null
git -C "$WORK" push -u origin current-gone >/dev/null
git -C "$WORK" push origin --delete current-gone >/dev/null
git -C "$WORK" fetch --prune >/dev/null
[ "$(git -C "$WORK" sweep)" = "current-gone" ]

for command in sweep-delete sweep-force; do
    if output="$(git -C "$WORK" "$command" 2>&1)"; then
        echo "git $command deleted the current branch" >&2
        exit 1
    fi
    [ -n "$output" ]
    printf '%s\n' "$output" | grep -q 'current-gone'
    git -C "$WORK" show-ref --verify --quiet refs/heads/current-gone
done

# Candidate generation must finish successfully before either deletion mode
# starts. A failing local alias overrides the generated global fixture alias.
git -C "$WORK" switch main >/dev/null
git -C "$WORK" config alias.sweep '!printf "SWEEP_CANDIDATE_SENTINEL\\n" >&2; exit 86'
for command in sweep-delete sweep-force; do
    set +e
    output="$(git -C "$WORK" "$command" 2>&1)"
    status=$?
    set -e
    [ "$status" -eq 86 ]
    printf '%s\n' "$output" | grep -q 'SWEEP_CANDIDATE_SENTINEL'
    git -C "$WORK" show-ref --verify --quiet refs/heads/current-gone
done
git -C "$WORK" config --unset alias.sweep

git -C "$WORK" sweep-force >/dev/null
[ -z "$(git -C "$WORK" sweep)" ]

printf 'Git sweep current-branch guards 2/2; candidate failure propagation 2/2\n'
printf 'Git sweep safety tests passed\n'
