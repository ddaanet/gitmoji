# gitmoji plugin — dev recipes

# Default: list recipes
_default:
    @just --list

# Validate manifest and script syntax
validate:
    jq . .claude-plugin/plugin.json > /dev/null
    bash -n scripts/gitmoji.sh
    bash -n scripts/install-hook.sh
    bash -n scripts/uninstall-hook.sh
    @echo "ok"

# Install the hook in the current git repo
install:
    bash scripts/install-hook.sh

# Uninstall the hook from the current git repo
uninstall:
    bash scripts/uninstall-hook.sh

# Test the hook against a sample commit message
test msg="feat: add a thing":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    trap 'rm -f "$tmp" "$tmp.tmp"' EXIT
    echo "{{msg}}" > "$tmp"
    echo "input:  {{msg}}"
    bash scripts/gitmoji.sh "$tmp" || { echo "hook failed"; exit 1; }
    echo "output: $(cat "$tmp")"
