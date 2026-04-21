# gitmoji plugin — dev recipes

# Default: list recipes
_default:
    @just --list

# Validate manifest and script syntax
validate:
    jq . .claude-plugin/plugin.json > /dev/null
    jq . hooks/hooks.json > /dev/null
    bash -n scripts/gitmoji.sh
    bash -n scripts/install-hook.sh
    bash -n scripts/uninstall-hook.sh
    bash -n scripts/session-materialize.sh
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

# Create release: bump plugin.json version, commit, tag, push, GH release
release bump='patch': validate
    #!/usr/bin/env bash
    set -euo pipefail
    manifest=".claude-plugin/plugin.json"
    git diff --quiet HEAD || { echo "error: uncommitted changes" >&2; exit 1; }
    branch=$(git symbolic-ref -q --short HEAD || echo "")
    [ "$branch" = "main" ] || { echo "error: must be on main (currently $branch)" >&2; exit 1; }
    new_version=$(jq -r --arg bump "{{bump}}" '
      (.version | split(".") | map(tonumber)) as [$maj,$min,$pat]
      | if   $bump == "major" then [$maj+1, 0, 0]
        elif $bump == "minor" then [$maj, $min+1, 0]
        elif $bump == "patch" then [$maj, $min, $pat+1]
        else error("unknown bump type: " + $bump) end
      | map(tostring) | join(".")
    ' "$manifest")
    tag="v$new_version"
    git rev-parse "$tag" >/dev/null 2>&1 && { echo "error: tag $tag already exists" >&2; exit 1; }
    read -rp "Release $new_version? [y/N] " answer
    case "$answer" in y|Y) ;; *) exit 1 ;; esac
    tmp=$(mktemp)
    jq --arg v "$new_version" '.version = $v' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
    git add "$manifest"
    git commit -m "chore: release $new_version"
    git tag -a "$tag" -m "Release $new_version"
    git push
    git push origin "$tag"
    gh release create "$tag" --title "Release $new_version" --generate-notes
    echo "Release $tag complete"
