#!/usr/bin/env bash
# Integration test: scripts/session-materialize.sh installs the
# commit-msg hook unconditionally when run inside a git repo, with
# NO settings.json flag present. Refuses to clobber a non-marker
# commit-msg. Silent no-op outside a git repo.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"

scratch_root="$(mktemp -d "$plugin_root/.test-materialize-XXXXXX")"
trap 'rm -rf "$scratch_root"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# --- Scenario 1: fresh git repo, no settings.json flag.
# The new materializer must install regardless of settings.
case1="$scratch_root/case1"
mkdir -p "$case1"
git -C "$case1" init -q

CLAUDE_PROJECT_DIR="$case1" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case1: materializer exited non-zero on fresh repo"

[ -f "$case1/.git/hooks/commit-msg" ]   || fail "case1: commit-msg not installed"
[ -x "$case1/.git/hooks/commit-msg" ]   || fail "case1: commit-msg not executable"
grep -q "gitmoji-plugin-installed" "$case1/.git/hooks/commit-msg" \
    || fail "case1: commit-msg missing marker"
[ -f "$case1/.git/hooks/gitmoji.sh" ]   || fail "case1: gitmoji.sh not installed"
[ -x "$case1/.git/hooks/gitmoji.sh" ]   || fail "case1: gitmoji.sh not executable"
[ -f "$case1/.git/hooks/gitmoji.cfg" ]  || fail "case1: gitmoji.cfg not installed"

# Confirm no settings.json was touched.
[ ! -f "$case1/.claude/settings.json" ] || fail "case1: materializer wrote settings.json"

# --- Scenario 2: existing marker-tagged commit-msg (upgrade path).
# Materializer should refresh files in place.
case2="$scratch_root/case2"
mkdir -p "$case2/.git/hooks"
git -C "$case2" init -q
cat > "$case2/.git/hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
# gitmoji-plugin-installed
# stale-content
EOF
chmod +x "$case2/.git/hooks/commit-msg"

CLAUDE_PROJECT_DIR="$case2" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case2: materializer exited non-zero on marker-tagged hook"

# After refresh, content should match the template verbatim.
diff "$case2/.git/hooks/commit-msg" "$plugin_root/scripts/commit-msg.template" \
    || fail "case2: commit-msg not refreshed to template content"
diff "$case2/.git/hooks/gitmoji.sh" "$plugin_root/scripts/gitmoji.sh" \
    || fail "case2: gitmoji.sh not refreshed"
diff "$case2/.git/hooks/gitmoji.cfg" "$plugin_root/scripts/gitmoji.cfg" \
    || fail "case2: gitmoji.cfg not refreshed"

# --- Scenario 3: foreign (non-marker) commit-msg present.
# Materializer must refuse to overwrite, warn, exit 0.
case3="$scratch_root/case3"
mkdir -p "$case3/.git/hooks"
git -C "$case3" init -q
cat > "$case3/.git/hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
# someone else's hook
echo "foreign hook"
EOF
chmod +x "$case3/.git/hooks/commit-msg"
foreign_sha=$(sha256sum "$case3/.git/hooks/commit-msg" | cut -d' ' -f1)

CLAUDE_PROJECT_DIR="$case3" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case3: materializer exited non-zero on foreign hook"

new_sha=$(sha256sum "$case3/.git/hooks/commit-msg" | cut -d' ' -f1)
[ "$foreign_sha" = "$new_sha" ] || fail "case3: materializer overwrote a foreign commit-msg"

# --- Scenario 4: outside a git repo. Silent exit 0.
# scratch_root sits inside the plugin's own git repo, so block git's
# walk-up via GIT_CEILING_DIRECTORIES — otherwise rev-parse would
# resolve case4 to the plugin repo and the materializer would try to
# write there.
case4="$scratch_root/case4"
mkdir -p "$case4"
GIT_CEILING_DIRECTORIES="$scratch_root" \
CLAUDE_PROJECT_DIR="$case4" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case4: materializer exited non-zero outside git repo"
[ ! -d "$case4/.git" ] || fail "case4: materializer created a .git directory"

echo "PASS"
