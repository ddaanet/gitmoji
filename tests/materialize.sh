#!/usr/bin/env bash
# Integration test: scripts/session-materialize.sh installs the
# commit-msg hook unconditionally when run inside a git repo, with
# NO settings.json flag present. Refuses to clobber a non-marker
# commit-msg. Silent no-op outside a git repo. Installs into the
# common hooks dir for linked worktrees and submodules; installs
# nothing where core.hooksPath moves git's hooks elsewhere, and installs
# as usual where it pins the default dir.
set -euo pipefail

# Isolate every git call, the materializer's included, from the
# user's and the system git config: a global core.hooksPath or
# commit.gpgsign would otherwise decide these cases.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"

scratch_root="$(mktemp -d "$plugin_root/.test-materialize-XXXXXX")"
trap 'rm -rf "$scratch_root"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# The additionalContext must state the form to write (a plain
# conventional prefix), not narrate the rewrite: an agent shown the
# rewrite imitates the emoji-prefixed git log. Same act in every
# installing state; no removal pointer in the agent channel.
assert_act_context() {
    local label="$1" out="$2"
    case "$out" in
        *'"additionalContext":"Start each commit message with a conventional-commit prefix'*'feat:'*'and no emoji; the gitmoji hook adds the emoji on commit."'*) ;;
        *) fail "$label: context does not state the prefix act, got: $out" ;;
    esac
    case "$out" in
        *"rewritten"*) fail "$label: context narrates the rewrite" ;;
        *"uninstall"*) fail "$label: context offers uninstall to the agent" ;;
    esac
}

# Make an empty commit with a fixed identity (the isolated config
# above supplies none).
commit_empty() {
    git -C "$1" -c user.name="gitmoji test" -c user.email=test@example.com \
        commit -q --allow-empty -m "feat: seed"
}

# core.hooksPath moves git's hooks away from the default dir: the
# materializer installs nothing and tells the agent nothing adds emoji.
# Its stderr names the default dir it left alone.
assert_hookspath_skip() {
    local label="$1" dir="$2" out="$3" err="$4" want_err
    case "$out" in
        *'"systemMessage":"gitmoji: core.hooksPath moves git'"'"'s hooks elsewhere — plugin hook not installed"'*) ;;
        *) fail "$label: wrong systemMessage, got: $out" ;;
    esac
    case "$out" in
        *'"additionalContext":"The gitmoji commit-msg hook is not installed here, so nothing adds emoji to commit messages. Follow this repository'"'"'s own commit-message convention."'*) ;;
        *) fail "$label: wrong additionalContext, got: $out" ;;
    esac
    want_err="gitmoji: core.hooksPath moves git's hooks away from $(cd "$dir/.git" && pwd -P)/hooks; not installing"
    [ "$err" = "$want_err" ] || fail "$label: wrong stderr, got: $err"
}

# --- Scenario 1: fresh git repo, no settings.json flag.
# The new materializer must install regardless of settings.
case1="$scratch_root/case1"
mkdir -p "$case1"
git -C "$case1" init -q

case1_out="$(CLAUDE_PROJECT_DIR="$case1" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case1: materializer exited non-zero on fresh repo"
assert_act_context case1 "$case1_out"
case "$case1_out" in
    *'"systemMessage":"gitmoji: installed commit-msg hook"'*) ;;
    *) fail "case1: expected 'installed' systemMessage, got: $case1_out" ;;
esac

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

case2_out="$(CLAUDE_PROJECT_DIR="$case2" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case2: materializer exited non-zero on marker-tagged hook"
assert_act_context case2 "$case2_out"
case "$case2_out" in
    *'"systemMessage":"gitmoji: refreshed commit-msg hook"'*) ;;
    *) fail "case2: expected 'refreshed' systemMessage, got: $case2_out" ;;
esac

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

case3_out="$(CLAUDE_PROJECT_DIR="$case3" bash "$plugin_root/scripts/session-materialize.sh")" \
    || fail "case3: materializer exited non-zero on foreign hook"

new_sha=$(sha256sum "$case3/.git/hooks/commit-msg" | cut -d' ' -f1)
[ "$foreign_sha" = "$new_sha" ] || fail "case3: materializer overwrote a foreign commit-msg"

# The message must state only what the script can verify: it must not
# pre-judge the foreign hook as "non-gitmoji" nor claim rewriting is
# "NOT active" (the foreign hook may itself rewrite). See BUGREPORT.
case "$case3_out" in
    *"NOT active"*)       fail "case3: message over-claims 'NOT active'" ;;
    *"non-gitmoji"*)      fail "case3: message pre-judges hook as 'non-gitmoji'" ;;
esac
case "$case3_out" in
    *"inspect it before assuming"*) ;;
    *) fail "case3: message missing 'inspect it before assuming' caveat" ;;
esac
# The agent channel must not offer removing someone else's hook, nor
# name the marker that would let the agent adopt it.
case "$case3_out" in
    *"remove"*)                   fail "case3: context offers removing the foreign hook" ;;
    *"gitmoji-plugin-installed"*) fail "case3: context names the ownership marker" ;;
    *"Start each commit message"*) fail "case3: context claims the plugin's act" ;;
esac

# --- Scenario 4: marker-tagged hook already current. Materializer
# should still succeed (idempotent) and report the `current` state.
case4_current="$scratch_root/case4_current"
mkdir -p "$case4_current"
git -C "$case4_current" init -q

CLAUDE_PROJECT_DIR="$case4_current" bash "$plugin_root/scripts/session-materialize.sh" >/dev/null \
    || fail "case4_current: first materialize exited non-zero"

current_out="$(CLAUDE_PROJECT_DIR="$case4_current" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case4_current: second materialize (idempotent) exited non-zero"

case "$current_out" in
    *'"systemMessage":"gitmoji: commit-msg hook already current"'*) ;;
    *) fail "case4_current: expected 'already current' systemMessage, got: $current_out" ;;
esac
assert_act_context case4_current "$current_out"

# --- Scenario 5: outside a git repo. Silent exit 0.
# scratch_root sits inside the plugin's own git repo, so block git's
# walk-up via GIT_CEILING_DIRECTORIES — otherwise rev-parse would
# resolve case5 to the plugin repo and the materializer would try to
# write there.
case5="$scratch_root/case5"
mkdir -p "$case5"
GIT_CEILING_DIRECTORIES="$scratch_root" \
CLAUDE_PROJECT_DIR="$case5" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case5: materializer exited non-zero outside git repo"
[ ! -d "$case5/.git" ] || fail "case5: materializer created a .git directory"

# --- Scenario 6: linked worktree. `.git` there is a file, so the hook
# must land in the common hooks dir of the main repo, shared by every
# worktree. The uninstaller, run from the worktree, removes it there.
case6="$scratch_root/case6"
case6_wt="$scratch_root/case6_wt"
mkdir -p "$case6"
git -C "$case6" init -q
commit_empty "$case6"
git -C "$case6" worktree add -q "$case6_wt" -b case6-wt
[ -f "$case6_wt/.git" ] || fail "case6: fixture worktree has no .git file"

case6_out="$(CLAUDE_PROJECT_DIR="$case6_wt" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case6: materializer exited non-zero in a linked worktree"
assert_act_context case6 "$case6_out"
case "$case6_out" in
    *'"systemMessage":"gitmoji: installed commit-msg hook"'*) ;;
    *) fail "case6: expected 'installed' systemMessage, got: $case6_out" ;;
esac
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ -f "$case6/.git/hooks/$f" ] || fail "case6: $f not in the main repo's hooks dir"
done

# Seed the common hooks dir directly so the uninstaller check does not
# depend on the materializer assertions above.
cp "$plugin_root/scripts/gitmoji.sh" "$plugin_root/scripts/gitmoji.cfg" "$case6/.git/hooks/"
cp "$plugin_root/scripts/commit-msg.template" "$case6/.git/hooks/commit-msg"
(cd "$case6_wt" && bash "$plugin_root/scripts/uninstall-hook.sh" >/dev/null) \
    || fail "case6: uninstaller exited non-zero in a linked worktree"
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ ! -e "$case6/.git/hooks/$f" ] || fail "case6: uninstaller left $f in the common hooks dir"
done

# --- Scenario 7: submodule. `.git` is a file pointing into the
# superproject's .git/modules/<name>; hooks install there.
case7_origin="$scratch_root/case7_origin"
case7="$scratch_root/case7"
mkdir -p "$case7_origin" "$case7"
git -C "$case7_origin" init -q
commit_empty "$case7_origin"
git -C "$case7" init -q
git -C "$case7" -c protocol.file.allow=always submodule add -q "$case7_origin" mod \
    || fail "case7: fixture submodule add failed"
[ -f "$case7/mod/.git" ] || fail "case7: fixture submodule has no .git file"

case7_out="$(CLAUDE_PROJECT_DIR="$case7/mod" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case7: materializer exited non-zero in a submodule"
assert_act_context case7 "$case7_out"
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ -f "$case7/.git/modules/mod/hooks/$f" ] || fail "case7: $f not under .git/modules/mod/hooks"
    [ ! -e "$case7/.git/hooks/$f" ] || fail "case7: $f leaked into the superproject's hooks dir"
done

# --- Scenario 8: core.hooksPath points at another tool's directory
# (husky, lefthook). Install nothing, write nothing, say so.
case8="$scratch_root/case8"
mkdir -p "$case8"
git -C "$case8" init -q
git -C "$case8" config core.hooksPath .husky
case8_before="$(ls -A "$case8/.git/hooks")"

case8_out="$(CLAUDE_PROJECT_DIR="$case8" bash "$plugin_root/scripts/session-materialize.sh" 2>"$scratch_root/case8.err")" \
    || fail "case8: materializer exited non-zero with core.hooksPath set"
assert_hookspath_skip case8 "$case8" "$case8_out" "$(cat "$scratch_root/case8.err")"
[ "$(ls -A "$case8/.git/hooks")" = "$case8_before" ] || fail "case8: .git/hooks changed"
[ ! -e "$case8/.husky" ] || fail "case8: materializer created .husky"

# --- Scenario 9: hook left in .git/hooks from before core.hooksPath was
# set. The uninstaller still removes it: the common hooks dir is the
# only place the plugin ever installs.
cp "$plugin_root/scripts/gitmoji.sh" "$plugin_root/scripts/gitmoji.cfg" "$case8/.git/hooks/"
cp "$plugin_root/scripts/commit-msg.template" "$case8/.git/hooks/commit-msg"
(cd "$case8" && bash "$plugin_root/scripts/uninstall-hook.sh" >/dev/null) \
    || fail "case9: uninstaller exited non-zero with core.hooksPath set"
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ ! -e "$case8/.git/hooks/$f" ] || fail "case9: uninstaller left $f behind"
done

# --- Scenario 10: core.hooksPath pins the default hooks dir by absolute
# path (tests/git-states.sh does this to shadow a global hooksPath).
# Git still reads that dir, so the hook installs there as usual.
case10="$scratch_root/case10"
mkdir -p "$case10/.git/hooks"
git -C "$case10" init -q
git -C "$case10" config core.hooksPath "$case10/.git/hooks"

case10_out="$(CLAUDE_PROJECT_DIR="$case10" bash "$plugin_root/scripts/session-materialize.sh" 2>/dev/null)" \
    || fail "case10: materializer exited non-zero with core.hooksPath pinning the default dir"
assert_act_context case10 "$case10_out"
case "$case10_out" in
    *'"systemMessage":"gitmoji: installed commit-msg hook"'*) ;;
    *) fail "case10: expected 'installed' systemMessage, got: $case10_out" ;;
esac
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ -f "$case10/.git/hooks/$f" ] || fail "case10: $f not installed in the pinned default dir"
done

# --- Scenario 11: empty core.hooksPath. Git then looks for hooks at
# the worktree root, not in the default dir, so install nothing there
# or anywhere else.
case11="$scratch_root/case11"
mkdir -p "$case11"
git -C "$case11" init -q
git -C "$case11" config core.hooksPath ""
case11_before="$(ls -A "$case11/.git/hooks")"

case11_out="$(CLAUDE_PROJECT_DIR="$case11" bash "$plugin_root/scripts/session-materialize.sh" 2>"$scratch_root/case11.err")" \
    || fail "case11: materializer exited non-zero with an empty core.hooksPath"
assert_hookspath_skip case11 "$case11" "$case11_out" "$(cat "$scratch_root/case11.err")"
[ "$(ls -A "$case11/.git/hooks")" = "$case11_before" ] || fail "case11: .git/hooks changed"
for f in commit-msg gitmoji.sh gitmoji.cfg; do
    [ ! -e "$case11/$f" ] || fail "case11: $f written to the worktree root"
done

echo "PASS"
