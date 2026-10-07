#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
REAL_GIT="$(command -v git)"
export REAL_GIT PROBE_LOG="$TEST_ROOT/calls" PROBE_FAIL=none
export FIXTURE_REPO="$TEST_ROOT/fixture" VCPKG_DISABLE_METRICS=1
PREFIX="$TEST_ROOT/brew"
PROVISION="$REPO_ROOT/scripts/cpp/provision-vcpkg.sh"
mkdir -p "$PREFIX/bin" "$FIXTURE_REPO/scripts/buildsystems" "$TEST_ROOT/poison"
touch "$FIXTURE_REPO/scripts/buildsystems/vcpkg.cmake"
cat >"$FIXTURE_REPO/bootstrap-vcpkg.sh" <<'EOF'
#!/bin/sh
printf 'bootstrap %s\n' "$*" >>"$PROBE_LOG"
[ "$1" = -disableMetrics ] || exit 95
[ "$PROBE_FAIL" != bootstrap ] || exit 31
cat >vcpkg <<'BIN'
#!/bin/sh
[ "$1" = version ] || exit 96
[ "$PROBE_FAIL" != version ] || exit 49
printf 'vcpkg fixture-version\n'
BIN
chmod +x vcpkg
EOF
"$REAL_GIT" -C "$FIXTURE_REPO" init --quiet
"$REAL_GIT" -C "$FIXTURE_REPO" add .
"$REAL_GIT" -C "$FIXTURE_REPO" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit --quiet -m fixture
cat >"$PREFIX/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PROBE_LOG"
[[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" ]] || exit 94
if [[ "$1" == clone ]]; then
    [[ "$PROBE_FAIL" != clone ]] || exit 47
    [[ "$2 $3" == '--no-checkout https://github.com/microsoft/vcpkg.git' ]]
    "$REAL_GIT" clone --quiet --no-checkout "$FIXTURE_REPO" "$4"
    "$REAL_GIT" -C "$4" remote set-url origin https://github.com/microsoft/vcpkg.git
elif [[ "$1" == -C && "$3" == checkout ]]; then
    [[ "$PROBE_FAIL" != checkout ]] || exit 48
    [[ "$4 $5" == '--detach 434307da09bc05b2c86996dccc8b2351fc0d5d37' ]]
    "$REAL_GIT" -C "$2" checkout --quiet --detach HEAD
else
    exec "$REAL_GIT" "$@"
fi
EOF
chmod +x "$PREFIX/bin/git"
printf '#!/bin/sh\nexit 97\n' >"$TEST_ROOT/poison/git"
chmod +x "$TEST_ROOT/poison/git"
export PATH="$TEST_ROOT/poison:$PATH"

expect_failure() {
    local expected="$1" status=0
    bash "$PROVISION" "$PREFIX" >"$TEST_ROOT/result" 2>&1 || status=$?
    [[ "$status" == "$expected" ]] || {
        cat "$TEST_ROOT/result"
        exit 1
    }
    ! grep -q '^vcpkg ready:' "$TEST_ROOT/result"
}

# Fresh XDG default, paths containing spaces, inherited Git poison, then no updates.
unset VCPKG_ROOT
export XDG_DATA_HOME="$TEST_ROOT/data with spaces"
GIT_DIR=/poison GIT_WORK_TREE=/poison bash "$PROVISION" "$PREFIX" >"$TEST_ROOT/result"
export VCPKG_ROOT="$XDG_DATA_HOME/vcpkg"
grep -Fq "vcpkg ready: $VCPKG_ROOT" "$TEST_ROOT/result"
printf 'user content\n' >"$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
before="$(grep -Ec '^(clone|bootstrap)| checkout ' "$PROBE_LOG")"
bash "$PROVISION" "$PREFIX" >"$TEST_ROOT/result"
[[ "$(grep -Ec '^(clone|bootstrap)| checkout ' "$PROBE_LOG")" == "$before" ]]
grep -qx 'user content' "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
! grep -Eq '(^| )(pull|reset|fetch)( |$)' "$PROBE_LOG"

# Repair only a missing executable, never bootstrap modified scripts or a fork.
mv "$VCPKG_ROOT/vcpkg" "$TEST_ROOT/vcpkg.saved"
cp "$VCPKG_ROOT/bootstrap-vcpkg.sh" "$TEST_ROOT/bootstrap.saved"
printf '# user edit\n' >>"$VCPKG_ROOT/bootstrap-vcpkg.sh"
expect_failure 1
cp "$TEST_ROOT/bootstrap.saved" "$VCPKG_ROOT/bootstrap-vcpkg.sh"
"$REAL_GIT" -C "$VCPKG_ROOT" remote set-url origin https://example.invalid/fork.git
expect_failure 1
"$REAL_GIT" -C "$VCPKG_ROOT" remote set-url origin https://github.com/microsoft/vcpkg.git
bash "$PROVISION" "$PREFIX" >"$TEST_ROOT/result"
grep -q '^vcpkg ready:' "$TEST_ROOT/result"

PROBE_FAIL=version expect_failure 49
chmod -x "$VCPKG_ROOT/vcpkg"
expect_failure 1
chmod +x "$VCPKG_ROOT/vcpkg"
mv "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" "$TEST_ROOT/toolchain.saved"
expect_failure 1
mv "$TEST_ROOT/toolchain.saved" "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"

# Failed fresh setup must not leave a target or an apparently ready installation.
for mode in clone checkout bootstrap; do
    case "$mode" in clone) code=47 ;; checkout) code=48 ;; bootstrap) code=31 ;; esac
    VCPKG_ROOT="$TEST_ROOT/new-$mode" PROBE_FAIL="$mode" expect_failure "$code"
    [[ ! -e "$TEST_ROOT/new-$mode" ]]
done
[[ -z "$(find "$TEST_ROOT" -name '.vcpkg-bootstrap.*' -print)" ]]
printf 'keep\n' >"$TEST_ROOT/occupied"
mkdir "$TEST_ROOT/not-a-repository"
ln -s "$VCPKG_ROOT" "$TEST_ROOT/link"
ln -s "$TEST_ROOT/missing" "$TEST_ROOT/dangling"
for invalid in occupied not-a-repository link dangling; do
    VCPKG_ROOT="$TEST_ROOT/$invalid" expect_failure 1
done
grep -qx keep "$TEST_ROOT/occupied"
[[ -L "$TEST_ROOT/link" && -L "$TEST_ROOT/dangling" ]]
VCPKG_ROOT=relative expect_failure 1

# Three platform templates: shared login/non-login owner, explicit project roots,
# project PATH precedence, and idempotent sourcing without invoking any tool.
ZSH_BIN="$(command -v zsh)"
for platform in arm intel linux; do
    case "$platform" in
        arm)
            data='{"is_mac":true,"is_linux":false,"is_arm64":true}'
            canonical=/opt/homebrew
            ;;
        intel)
            data='{"is_mac":true,"is_linux":false,"is_arm64":false}'
            canonical=/usr/local
            ;;
        linux)
            data='{"is_mac":false,"is_linux":true,"is_arm64":false}'
            canonical=/home/linuxbrew/.linuxbrew
            ;;
    esac
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_26_vcpkg.sh.tmpl" >"$TEST_ROOT/setup"
    grep -Fq "BREW_PREFIX=\"$canonical\"" "$TEST_ROOT/setup"
    sed -i.bak "s#$canonical#$PREFIX#g" "$TEST_ROOT/setup"
    bash "$TEST_ROOT/setup" >"$TEST_ROOT/result"
    grep -Fq "vcpkg ready: $VCPKG_ROOT" "$TEST_ROOT/result"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$REPO_ROOT/home/dot_config/zsh/homebrew.zsh.tmpl" >"$TEST_ROOT/owner"
    env -u VCPKG_ROOT OWNER="$TEST_ROOT/owner" "$ZSH_BIN" -dfc '
        source "$OWNER"
        [[ "$VCPKG_ROOT" == "$XDG_DATA_HOME/vcpkg" && "${path[(Ie)$VCPKG_ROOT]}" -gt 0 ]] || exit 51
        initial="$PATH"
        source "$OWNER"
        [[ "$PATH" == "$initial" ]] || exit 52
    '
    env VCPKG_ROOT="$TEST_ROOT/project vcpkg" OWNER="$TEST_ROOT/owner" \
        PATH="$TEST_ROOT/poison:/usr/bin:/bin" "$ZSH_BIN" -dfc '
        expected="$VCPKG_ROOT"; first="${path[1]}"
        source "$OWNER"
        [[ "$VCPKG_ROOT" == "$expected" && "${path[1]}" == "$first" ]] || exit 53
        [[ "${path[(Ie)$VCPKG_ROOT]}" -gt 0 ]] || exit 54
    '
done

# Exercise the actual doctor block; no host inspection or repair in this probe.
printf 'check_status() { printf "%%s|%%s|%%s\\n" "$1" "$2" "$3"; }\n' >"$TEST_ROOT/doctor"
sed -n '/^# Check the same root/,/^if command -v terraform/{ /^if command -v terraform/!p; }' \
    "$REPO_ROOT/home/dot_config/zsh/scripts/executable_doctor.sh.tmpl" >>"$TEST_ROOT/doctor"
bash "$TEST_ROOT/doctor" >"$TEST_ROOT/result"
grep -Fq '|pass|' "$TEST_ROOT/result"
PROBE_FAIL=version bash "$TEST_ROOT/doctor" >"$TEST_ROOT/result"
grep -Fq '|warn|vcpkg failed' "$TEST_ROOT/result"
VCPKG_ROOT="$TEST_ROOT/missing" bash "$TEST_ROOT/doctor" >"$TEST_ROOT/result"
grep -Fq '|warn|Incomplete checkout' "$TEST_ROOT/result"
env -u VCPKG_ROOT bash "$TEST_ROOT/doctor" >"$TEST_ROOT/result"
grep -Fq '|warn|VCPKG_ROOT unset' "$TEST_ROOT/result"
printf 'vcpkg missing-only setup, failure propagation, environment and diagnostics: PASS\n'
