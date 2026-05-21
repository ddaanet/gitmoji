#!/usr/bin/env bash
# Materialize (install or refresh) the per-repo commit-msg hook from
# this invocation's plugin version. Runs on every SessionStart in
# repos where the plugin is enabled (resolved via Claude Code's
# enabledPlugins). When this script runs, the plugin is enabled here,
# so install unconditionally; never tear down. Refuses to overwrite a
# foreign commit-msg without the `gitmoji-plugin-installed` marker.
# Idempotent.
#
# Output protocol:
# - stderr: human-readable line including the target path (kept for
#   terminal/debug logs).
# - stdout: SessionStart hook JSON with `systemMessage` (one-line
#   status hint surfaced by Claude Code) and
#   `hookSpecificOutput.additionalContext` (added to Claude's
#   session context so the agent knows what the hook does in this
#   repo).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    exit 0
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

# Bash JSON string escape. Hook content is plugin-controlled, but the
# target path is user-controlled (could contain quotes/backslashes).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_hook_output() {
    local system_msg="$1" context="$2"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"},"systemMessage":"%s"}\n' \
        "$(json_escape "$context")" \
        "$(json_escape "$system_msg")"
}

mkdir -p "$hooks_dir"

# Foreign commit-msg (no marker): refuse to overwrite.
if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "gitmoji: existing commit-msg hook at $target; leaving alone (move it to enable)" >&2
    emit_hook_output \
        "gitmoji: existing commit-msg hook left alone (move or delete to enable)" \
        "A non-gitmoji commit-msg hook is present in this repository. The plugin refuses to overwrite it; commit-message rewriting is NOT active here until the existing hook is removed."
    exit 0
fi

# Decide state before writing. `installed` means there was nothing
# here; `current` means the candidate files are byte-identical to
# what's already installed; `updated` means a marker-tagged hook is
# present but differs from this plugin version.
if [[ ! -f "$target" ]]; then
    state="installed"
elif cmp -s "$script_dir/commit-msg.template" "$target" \
    && cmp -s "$script_dir/gitmoji.sh" "$hooks_dir/gitmoji.sh" \
    && cmp -s "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"; then
    state="current"
else
    state="updated"
fi

cp "$script_dir/gitmoji.sh"  "$hooks_dir/gitmoji.sh"
cp "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"
chmod +x "$hooks_dir/gitmoji.sh"
cp "$script_dir/commit-msg.template" "$target"
chmod +x "$target"

case "$state" in
    installed)
        echo "gitmoji: installed commit-msg hook at $target" >&2
        emit_hook_output \
            "gitmoji: installed commit-msg hook" \
            "The gitmoji commit-msg hook was newly installed in this repository. Conventional-commit prefixes (feat:, fix:, docs:, ...) will be rewritten with emoji on commit. Run /gitmoji:uninstall to remove."
        ;;
    updated)
        echo "gitmoji: refreshed commit-msg hook at $target" >&2
        emit_hook_output \
            "gitmoji: refreshed commit-msg hook" \
            "The gitmoji commit-msg hook in this repository was refreshed to match the current plugin version."
        ;;
    current)
        echo "gitmoji: commit-msg hook already current at $target" >&2
        emit_hook_output \
            "gitmoji: commit-msg hook already current" \
            "gitmoji's commit-msg hook is installed in this repository. Conventional-commit prefixes are rewritten with emoji on commit."
        ;;
esac
