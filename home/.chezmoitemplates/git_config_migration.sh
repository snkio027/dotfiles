# Read-only comparison helpers, also sourced directly by disposable-fixture tests.
git_config_migration_values() (
    set -o pipefail
    # Keep record boundaries and entry order. Sorting loses last-value precedence
    # and the order of multivars such as credential.helper and remote.*.fetch.
    git config --file "$1" --no-includes --null --list |
        while IFS= read -r -d '' entry; do
            key="${entry%%$'\n'*}"
            case "$key" in
                # Includes can depend on the original file's directory or the
                # current repository. Leave both absolute and relative includes
                # for manual review instead of comparing their literal paths.
                include.path | includeif.*.path) return 1 ;;
            esac
            value="${entry#*$'\n'}"
            case "$value" in
                # Multiline values need manual review, even when identical.
                *$'\n'*) return 1 ;;
            esac
            printf '%s\0' "$entry"
        done | od -An -v -tx1
)

git_configs_match_for_migration() {
    local legacy_values xdg_values
    # Hex encoding keeps NUL separators intact across command substitution;
    # failures must not become two equal empty snapshots.
    legacy_values="$(git_config_migration_values "$1")" || return 1
    xdg_values="$(git_config_migration_values "$2")" || return 1
    [ "$legacy_values" = "$xdg_values" ]
}
