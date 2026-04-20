#!/usr/bin/env bash
# Install the gitmoji commit-msg hook into the current git repository.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

mkdir -p "$hooks_dir"

if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "existing commit-msg hook at $target" >&2
    echo "move or remove it first to avoid overwriting" >&2
    exit 1
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

echo "installed commit-msg hook at $target"
