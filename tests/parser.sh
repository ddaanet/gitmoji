#!/usr/bin/env bash
# Unit tests for scripts/gitmoji.sh: parses the Conventional Commits
# 1.0.0 first-line grammar and renders scope + breaking-change
# information into the rewritten subject.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$plugin_root/scripts/gitmoji.sh"

scratch="$(mktemp -d "$plugin_root/.test-parser-XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

fail=0
total=0

assert_rewrite() {
    local input="$1" expected="$2" name="$3"
    total=$((total+1))
    local f="$scratch/msg-$total"
    printf '%s\n' "$input" > "$f"
    if ! bash "$hook" "$f" 2>/dev/null; then
        echo "FAIL: $name (hook exited non-zero on '$input')"
        fail=$((fail+1)); return
    fi
    local got; got="$(head -n1 "$f")"
    if [ "$got" = "$expected" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        echo "  input:    $input"
        echo "  expected: $expected"
        echo "  got:      $got"
        fail=$((fail+1))
    fi
}

assert_skip() {
    local input="$1" name="$2"
    total=$((total+1))
    local f="$scratch/msg-$total"
    printf '%s\n' "$input" > "$f"
    if ! bash "$hook" "$f" 2>/dev/null; then
        echo "FAIL: $name (hook exited non-zero)"
        fail=$((fail+1)); return
    fi
    local got; got="$(head -n1 "$f")"
    if [ "$got" = "$input" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (message was modified)"
        echo "  input: $input"
        echo "  got:   $got"
        fail=$((fail+1))
    fi
}

assert_reject() {
    local input="$1" want_stderr="$2" name="$3"
    total=$((total+1))
    local f="$scratch/msg-$total"
    printf '%s\n' "$input" > "$f"
    local stderr
    if stderr="$(bash "$hook" "$f" 2>&1 >/dev/null)"; then
        echo "FAIL: $name (hook accepted '$input')"
        fail=$((fail+1)); return
    fi
    if printf '%s' "$stderr" | grep -qF "$want_stderr"; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (stderr missing '$want_stderr')"
        echo "  input:  $input"
        echo "  stderr: $stderr"
        fail=$((fail+1))
    fi
}

assert_source_type_skip() {
    local input="$1" source_type="$2" name="$3"
    total=$((total+1))
    local f="$scratch/msg-$total"
    printf '%s\n' "$input" > "$f"
    if ! bash "$hook" "$f" "$source_type" 2>/dev/null; then
        echo "FAIL: $name (hook exited non-zero, source_type=$source_type)"
        fail=$((fail+1)); return
    fi
    local got; got="$(head -n1 "$f")"
    if [ "$got" = "$input" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (source_type=$source_type rewrote message)"
        fail=$((fail+1))
    fi
}

# --- Happy path: the four shapes in the spec's rendering table.
assert_rewrite "feat: add login"              "✨ add login"                "feat: simple"
assert_rewrite "feat!: drop python 3.8"       "✨💥 drop python 3.8"        "feat: bang"
assert_rewrite "feat(api): add endpoint"      "✨ api: add endpoint"        "feat: scope"
assert_rewrite "feat(api)!: rename endpoint" "✨💥 api: rename endpoint"   "feat: scope+bang"

# Second type: all four shapes again.
assert_rewrite "fix: handle null"             "🐛 handle null"              "fix: simple"
assert_rewrite "fix!: drop legacy path"       "🐛💥 drop legacy path"       "fix: bang"
assert_rewrite "fix(core): off-by-one"        "🐛 core: off-by-one"         "fix: scope"
assert_rewrite "fix(core)!: drop legacy path" "🐛💥 core: drop legacy path" "fix: scope+bang"

# Scope character class: hyphen, dot, slash, underscore, digit.
assert_rewrite "docs(nav-bar): update"        "📝 nav-bar: update"         "scope: hyphen"
assert_rewrite "docs(v2.0): update"           "📝 v2.0: update"            "scope: dot"
assert_rewrite "docs(core/utils): update"     "📝 core/utils: update"      "scope: slash"
assert_rewrite "docs(snake_case): update"     "📝 snake_case: update"      "scope: underscore"
assert_rewrite "docs(api2): update"           "📝 api2: update"            "scope: digit"

# --- Already-emoji skip (round-trip idempotence).
assert_skip "✨ already done"           "skip: type emoji"
assert_skip "✨💥 already done"         "skip: type+boom (round-trip)"

# --- Rejections (each error branch).
assert_reject "💥 break things" "Missing or malformed" "reject: bare boom"
assert_reject "xyz: msg"        "Unknown prefix"       "reject: unknown type"
assert_reject "feat(): msg"     "Empty scope"          "reject: empty scope"
assert_reject "feat()!: msg"    "Empty scope"          "reject: empty scope + bang"
assert_reject "feat:msg"        "Missing or malformed" "reject: no space after colon"
assert_reject "Feat: msg"       "Missing or malformed" "reject: uppercase type"
assert_reject "feat(BAD): msg"  "Missing or malformed" "reject: uppercase scope"
assert_reject "feat: "          "Missing or malformed" "reject: empty description"
assert_reject "feat msg"        "Missing or malformed" "reject: no colon"

# --- Source-type skips (merge / squash / amend remain no-ops).
assert_source_type_skip "feat: foo" "merge"  "source: merge no-op"
assert_source_type_skip "feat: foo" "squash" "source: squash no-op"
assert_source_type_skip "feat: foo" "commit" "source: commit (amend) no-op"

echo
if [ "$fail" -gt 0 ]; then
    echo "FAIL: $fail of $total cases"
    exit 1
fi
echo "PASS: $total cases"
