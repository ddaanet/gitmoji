import 'plugin-dev/release.just'

# gitmoji plugin — dev recipes
#
# `precommit` is the gate that runs before every commit: it lints the
# manifests + hooks.json and shellchecks the scripts.
#
# `prerelease` is the gate the imported `release` recipe depends on.
# Here it is exactly `precommit`; widen it if the release ever needs
# checks too slow or too costly to fire on every commit.
#
# The test recipes, in more detail than their one-line doc comments fit:
#   test-materialize — asserts the SessionStart materializer installs the
#     hook unconditionally when invoked, with marker-protection on
#     pre-existing non-gitmoji commit-msg hooks.
#   test-uninstall — asserts the slash command removes the hook files
#     without touching `.claude/settings.json`.
#   test-parser — parsing/rendering of the Conventional Commits 1.0.0
#     first-line grammar.
#   test-git-states — drives real git commands to assert the hook
#     leaves git-authored messages alone (merge, squash-merge,
#     cherry-pick/revert conflict continuations, autosquash). The
#     signal is a state marker in the git dir, which only exists
#     during a real operation, so it cannot be unit-tested.

# Default: list recipes
_default:
    @just --list

# Lint manifests + hooks.json, run shellcheck on scripts
precommit:
    jq . .claude-plugin/plugin.json > /dev/null
    jq . hooks/hooks.json > /dev/null
    shellcheck -x scripts/*.sh tests/*.sh
    @echo "ok"

# Gate the imported `release` recipe depends on
prerelease: precommit

# Run the SessionStart materializer against the current repo (dev loop)
materialize:
    CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)" bash scripts/session-materialize.sh

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

# Integration test: SessionStart materializer installs the per-repo hook
test-materialize:
    bash tests/materialize.sh

# Integration test: /gitmoji:uninstall removes the hook via `claude -p`
test-uninstall:
    bash tests/uninstall.sh

# Unit tests for scripts/gitmoji.sh — the first-line grammar parser
test-parser:
    bash tests/parser.sh

# Integration test: git-authored messages survive the hook untouched
test-git-states:
    bash tests/git-states.sh

# Run all tests (parser unit tests + integration tests).
test-integration: test-parser test-git-states test-materialize test-uninstall