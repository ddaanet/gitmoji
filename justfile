import 'plugin-dev/release.just'

# gitmoji plugin — dev recipes

# Default: list recipes
_default:
    @just --list

# Lint manifests + hooks.json, run shellcheck on scripts.
# Imported `release` recipe depends on this name.
precommit:
    jq . .claude-plugin/plugin.json > /dev/null
    jq . hooks/hooks.json > /dev/null
    shellcheck -x scripts/*.sh
    @echo "ok"

# Run the SessionStart materializer against the current repo (dev loop)
materialize:
    CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)" bash scripts/session-materialize.sh

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

# Integration test: SessionStart materializer installs the per-repo
# hook unconditionally when invoked, with marker-protection on
# non-gitmoji commit-msg hooks.
test-materialize:
    bash tests/materialize.sh

# Integration test: drive /gitmoji:uninstall via `claude -p` and assert
# the slash command removes the hook files without touching
# `.claude/settings.json`.
test-uninstall:
    bash tests/uninstall.sh

# Run all integration tests.
test-integration: test-materialize test-uninstall