#!/usr/bin/env bash
# Integration test: the commit-msg hook leaves git-authored messages
# alone. Git generates the message for merges, squash-merges, and
# conflict continuations of cherry-pick/revert; those are not the
# user's to make conventional, and rejecting them strands the
# operation ("Not committing merge; use 'git commit' to complete").
#
# These cases cannot be covered by tests/parser.sh: the signal is a
# state marker in the git dir, which only exists during a real git
# operation. Everything here therefore drives actual git commands.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"

# Real repos, kept outside the plugin's own working tree so a nested
# .git can never be confused with the plugin repo's.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

fail=0
total=0

report() {
    local ok="$1" name="$2" detail="${3:-}"
    total=$((total+1))
    if [ "$ok" = yes ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        if [ -n "$detail" ]; then
            echo "  $detail"
        fi
        fail=$((fail+1))
    fi
}

subject() { git -C "$1" log -1 --pretty=%s; }

assert_subject() {
    local dir="$1" want="$2" name="$3" got
    got="$(subject "$dir")"
    if [ "$got" = "$want" ]; then
        report yes "$name"
    else
        report no "$name" "want: [$want]  got: [$got]"
    fi
}

# Install the hook exactly as the materializer does: all three files
# side by side in .git/hooks, since commit-msg.template resolves
# gitmoji.sh relative to its own location. core.hooksPath is pinned
# explicitly so a global hooksPath in the developer's environment
# cannot shadow it.
setup_repo() {
    local dir="$1"
    mkdir -p "$dir/.git/hooks"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name "gitmoji test"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config core.hooksPath "$dir/.git/hooks"
    cp "$plugin_root/scripts/commit-msg.template" "$dir/.git/hooks/commit-msg"
    cp "$plugin_root/scripts/gitmoji.sh" "$dir/.git/hooks/gitmoji.sh"
    cp "$plugin_root/scripts/gitmoji.cfg" "$dir/.git/hooks/gitmoji.cfg"
    chmod +x "$dir/.git/hooks/commit-msg" "$dir/.git/hooks/gitmoji.sh"
    echo base > "$dir/f.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "feat: base"
}

# Two divergent branches touching different files (clean merge).
diverge_clean() {
    local d="$1"
    git -C "$d" checkout -q -b side
    echo s > "$d/s.txt"; git -C "$d" add -A; git -C "$d" commit -q -m "feat: side"
    git -C "$d" checkout -q main
    echo m > "$d/m.txt"; git -C "$d" add -A; git -C "$d" commit -q -m "feat: main"
}

# Two divergent branches touching the SAME file (conflicting merge).
#
# The side commit is made with --no-verify so its subject stays raw and
# non-conventional. That matters for the cherry-pick case: a conflict
# continuation replays the original subject, and if that subject were
# already emoji-rewritten the hook would exit via the round-trip check
# and the state-marker guard would never be exercised.
diverge_conflict() {
    local d="$1"
    git -C "$d" checkout -q -b side
    echo side-value > "$d/f.txt"; git -C "$d" add -A
    git -C "$d" commit -q --no-verify -m "side change, deliberately not conventional"
    git -C "$d" checkout -q main
    echo main-value > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -q -m "feat: main"
}

# --- Case 1: plain merge with git's auto-generated message.
name="merge: auto message preserved"
d="$scratch/merge-plain"; setup_repo "$d"; diverge_clean "$d"
if git -C "$d" merge --no-edit side >/dev/null 2>&1; then
    assert_subject "$d" "Merge branch 'side'" "$name"
else
    report no "$name" "merge exited non-zero (hook rejected the message)"
fi

# --- Case 2: merging a raw commit-ish yields "Merge commit '<sha>'",
# the shape `git subtree pull --squash` generates and the one that
# prompted this work.
name="merge: 'Merge commit <sha>' preserved"
d="$scratch/merge-sha"; setup_repo "$d"; diverge_clean "$d"
side_sha="$(git -C "$d" rev-parse side)"
if git -C "$d" merge --no-edit "$side_sha" >/dev/null 2>&1; then
    assert_subject "$d" "Merge commit '$side_sha'" "$name"
else
    report no "$name" "merge exited non-zero (hook rejected the message)"
fi

# --- Case 3: conflicted merge completed by `git commit`. Git passes
# COMMIT_EDITMSG here, not MERGE_MSG, so the message-file basename is
# not a sufficient signal — only MERGE_HEAD still being present is.
name="merge: conflict continuation preserved"
d="$scratch/merge-conflict"; setup_repo "$d"; diverge_conflict "$d"
git -C "$d" merge --no-edit side >/dev/null 2>&1 || true
echo resolved > "$d/f.txt"; git -C "$d" add -A
if git -C "$d" commit -q --no-edit >/dev/null 2>&1; then
    assert_subject "$d" "Merge branch 'side'" "$name"
else
    report no "$name" "commit exited non-zero (hook rejected the message)"
fi

# --- Case 4: squash merge. Marker is SQUASH_MSG, not MERGE_HEAD.
name="merge --squash: message preserved"
d="$scratch/merge-squash"; setup_repo "$d"; diverge_clean "$d"
git -C "$d" merge -q --squash side >/dev/null 2>&1
if git -C "$d" commit -q --no-edit >/dev/null 2>&1; then
    assert_subject "$d" "Squashed commit of the following:" "$name"
else
    report no "$name" "commit exited non-zero (hook rejected the message)"
fi

# --- Case 5: conflicted cherry-pick completed by `git commit`.
# A clean cherry-pick never invokes commit-msg at all; only the
# conflict continuation reaches the hook, with CHERRY_PICK_HEAD set.
name="cherry-pick: conflict continuation preserved"
d="$scratch/cherry-pick"; setup_repo "$d"; diverge_conflict "$d"
picked="$(git -C "$d" log -1 --pretty=%s side)"
git -C "$d" cherry-pick side >/dev/null 2>&1 || true
echo resolved > "$d/f.txt"; git -C "$d" add -A
if git -C "$d" commit -q --no-edit >/dev/null 2>&1; then
    assert_subject "$d" "$picked" "$name"
else
    report no "$name" "commit exited non-zero"
fi

# --- Case 6: conflicted revert completed by `git commit`.
# Git's "Revert \"...\"" subject is not conventional and must survive.
name="revert: conflict continuation preserved"
d="$scratch/revert"; setup_repo "$d"
echo v2 > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -q -m "feat: v2"
echo v3 > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -q -m "feat: v3"
# The reverted commit's own subject was rewritten on the way in, so
# git quotes the emoji form here. Compute it rather than hardcoding.
reverted="$(git -C "$d" log -1 --pretty=%s HEAD~1)"
git -C "$d" revert --no-edit HEAD~1 >/dev/null 2>&1 || true
echo resolved > "$d/f.txt"; git -C "$d" add -A
if git -C "$d" commit -q --no-edit >/dev/null 2>&1; then
    assert_subject "$d" "Revert \"$reverted\"" "$name"
else
    report no "$name" "commit exited non-zero"
fi

# --- Case 7: autosquash. No state marker exists; the `fixup! ` subject
# prefix is the only signal, so this exercises the regex against real git.
name="commit --fixup: subject preserved"
d="$scratch/fixup"; setup_repo "$d"
# git builds the subject as "fixup! <subject of the target commit>",
# and that target was rewritten on the way in, so compute it.
target="$(git -C "$d" log -1 --pretty=%s)"
echo y > "$d/y.txt"; git -C "$d" add -A
if git -C "$d" commit -q --fixup HEAD >/dev/null 2>&1; then
    assert_subject "$d" "fixup! $target" "$name"
else
    report no "$name" "commit exited non-zero (hook rejected the message)"
fi

# --- Negative 1: the guard must not disable ordinary rewriting.
d="$scratch/ordinary"; setup_repo "$d"
assert_subject "$d" "✨ base" "ordinary commit still rewritten"

# --- Negative 2: no marker may outlive its operation. If MERGE_HEAD
# lingered, every later commit would silently stop being rewritten.
name="commit after merge still rewritten"
d="$scratch/after-merge"; setup_repo "$d"; diverge_clean "$d"
git -C "$d" merge --no-edit side >/dev/null 2>&1 || true
echo later > "$d/later.txt"; git -C "$d" add -A
if git -C "$d" commit -q -m "fix: after the merge" >/dev/null 2>&1; then
    assert_subject "$d" "🐛 after the merge" "$name"
else
    report no "$name" "commit exited non-zero"
fi

echo
if [ "$fail" -gt 0 ]; then
    echo "FAIL: $fail of $total cases"
    exit 1
fi
echo "PASS: $total cases"
