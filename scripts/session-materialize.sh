#!/usr/bin/env bash
# Materialize (install or refresh) the per-repo commit-msg hook from
# this invocation's plugin version. Runs on every SessionStart in
# repos where the plugin is enabled (resolved via Claude Code's
# enabledPlugins). When this script runs, the plugin is enabled here,
# so install unconditionally; never tear down. Refuses to overwrite a
# foreign commit-msg without the `gitmoji-plugin-installed` marker, and
# installs nothing where core.hooksPath moves git's hooks dir
# elsewhere. Idempotent.
#
# Output protocol:
# - stderr: human-readable line including the target path (kept for
#   terminal/debug logs).
# - stdout: SessionStart hook JSON with `systemMessage` (one-line
#   status hint surfaced by Claude Code) and
#   `hookSpecificOutput.additionalContext` (added to Claude's
#   session context: the commit-message form the agent should write).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
if ! git -C "$project_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    exit 0
fi

# The default hooks dir, shared by every linked worktree of a repo; a
# submodule's lives under the superproject's .git/modules. `.git` is a
# file in both, so "<toplevel>/.git/hooks" is not a path there.
# rev-parse prints the common dir relative to the cwd or absolute;
# resolve it with cd/pwd rather than --path-format (git >= 2.31).
# Physical (-P), so the core.hooksPath comparison below is not fooled
# by a symlink on one side.
hooks_dir="$(cd "$project_dir" && CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd -P)/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

# Bash JSON string escape for backslash, ", \n, \r and \t only. Callers pass
# constant strings, never variable data such as $target, so this is
# not safe for arbitrary paths containing other control characters.
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

# core.hooksPath, at any scope, can move git's hooks dir away from
# $hooks_dir: husky and lefthook point it at a checked-in directory
# another tool owns, and an empty value leaves the hooks dir at the
# worktree root. A hook in $hooks_dir would then never fire, and the
# other dir is not ours to write. A hooksPath naming $hooks_dir itself
# only pins the default, so install as usual. Unset, git's hooks dir
# is $hooks_dir by definition (it may not exist yet, so do not cd).
if git -C "$project_dir" config --get core.hooksPath >/dev/null; then
    git_hooks_dir="$(cd "$project_dir" && CDPATH='' cd -- "$(git rev-parse --git-path hooks)" 2>/dev/null && pwd -P)" \
        || git_hooks_dir=""
    if [[ "$git_hooks_dir" != "$hooks_dir" ]]; then
        echo "gitmoji: core.hooksPath moves git's hooks away from $hooks_dir; not installing" >&2
        emit_hook_output \
            "gitmoji: core.hooksPath moves git's hooks elsewhere — plugin hook not installed" \
            "The gitmoji commit-msg hook is not installed here, so nothing adds emoji to commit messages. Follow this repository's own commit-message convention."
        exit 0
    fi
fi

mkdir -p "$hooks_dir"

# Foreign commit-msg (no marker): refuse to overwrite.
if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "gitmoji: existing commit-msg hook at $target; leaving alone (move it to enable)" >&2
    emit_hook_output \
        "gitmoji: existing commit-msg hook present — plugin hook not installed (inspect the existing hook)" \
        "The commit-msg hook in this repository was not installed by the gitmoji plugin and was left in place. Read it to learn what commit-message form it expects; inspect it before assuming it adds emoji."
    exit 0
fi

# Decide status before writing. "installed" means there was nothing
# here; "already current" means the candidate files are byte-identical
# to what's already installed; "refreshed" means a marker-tagged hook
# is present but differs from this plugin version.
if [[ ! -f "$target" ]]; then
    status="installed commit-msg hook"
elif cmp -s "$script_dir/commit-msg.template" "$target" \
    && cmp -s "$script_dir/gitmoji.sh" "$hooks_dir/gitmoji.sh" \
    && cmp -s "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"; then
    status="commit-msg hook already current"
else
    status="refreshed commit-msg hook"
fi

cp "$script_dir/gitmoji.sh"  "$hooks_dir/gitmoji.sh"
cp "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"
chmod +x "$hooks_dir/gitmoji.sh"
cp "$script_dir/commit-msg.template" "$target"
chmod +x "$target"

# Same agent-facing act in every installing state: name the form to
# write, never the rewritten output the agent already sees in git log.
act_context="Start each commit message with a conventional-commit prefix (feat:, fix:, docs:, ...) and no emoji; the gitmoji hook adds the emoji on commit."

echo "gitmoji: $status at $target" >&2
emit_hook_output "gitmoji: $status" "$act_context"
