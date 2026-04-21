#!/usr/bin/env bash
# Materialize or tear down the per-repo commit-msg hook based on the
# effective `gitmoji.enabled` setting across Claude Code's settings.json
# hierarchy (local > project > user). Idempotent; safe to run on every
# SessionStart. Always writes hook files from this invocation's plugin
# version, so plugin upgrades propagate on the next session.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "gitmoji: jq not found on PATH; skipping" >&2
    exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    exit 0
fi

read_setting() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    jq -r '.gitmoji.enabled | values' "$file" 2>/dev/null || true
}

enabled=""
for f in \
    "$repo_root/.claude/settings.local.json" \
    "$repo_root/.claude/settings.json" \
    "$HOME/.claude/settings.json"
do
    v="$(read_setting "$f")"
    if [[ -n "$v" ]]; then
        enabled="$v"
        break
    fi
done

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

if [[ "$enabled" == "true" ]]; then
    mkdir -p "$hooks_dir"
    if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
        echo "gitmoji: existing commit-msg hook at $target; leaving alone (move it to enable)" >&2
        exit 0
    fi
    cp "$script_dir/gitmoji.sh"  "$hooks_dir/gitmoji.sh"
    cp "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"
    chmod +x "$hooks_dir/gitmoji.sh"
    cat > "$target" <<EOF
#!/usr/bin/env bash
# $marker
exec "\$(dirname "\$0")/gitmoji.sh" "\$@"
EOF
    chmod +x "$target"
    echo "gitmoji: materialized commit-msg hook at $target"
else
    if [[ -f "$target" ]] && grep -q "$marker" "$target" 2>/dev/null; then
        rm -f "$target" "$hooks_dir/gitmoji.sh" "$hooks_dir/gitmoji.cfg"
        echo "gitmoji: removed commit-msg hook at $target"
    fi
fi
