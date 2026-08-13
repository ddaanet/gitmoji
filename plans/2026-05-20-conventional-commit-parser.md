# Conventional commit parser — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `scripts/gitmoji.sh` to parse the full Conventional Commits 1.0.0 first-line grammar — `type[(scope)][!]: description` — and render scope/breaking-change information into the rewritten subject.

**Architecture:** Single bash regex with optional groups, plus a second regex for empty-scope detection so the error message can be specific. `💥` is a script-local constant (the `BOOM` variable), not a parseable type. The already-emoji skip list is unchanged, so bare `💥 msg` is rejected and round-tripped `✨💥 msg` passes through on the leading `✨`.

**Tech Stack:** bash, shellcheck.

**Spec:** [`2026-05-20-conventional-commit-parser-design.md`](2026-05-20-conventional-commit-parser-design.md).

---

## File structure

| File | Responsibility |
|---|---|
| `tests/parser.sh` *(new)* | Table-driven unit tests for the parser: happy path, skip cases, every rejection branch, source-type no-ops. |
| `scripts/gitmoji.sh` *(modify)* | Replace the body of the parse/render branch. Add `BOOM` constant, two regexes, helper for the prefix listing. |
| `justfile` *(modify)* | New `test-parser` recipe; add it to `test-integration`. |
| `README.md` *(modify)* | New examples table; add "Scope" and "Breaking changes" subsections. |
| `DESIGN.md` *(modify)* | Update the "Safety rules" grammar bullet; add `BREAKING CHANGE:` footer to "Non-goals". |

Unchanged: `scripts/gitmoji.cfg` (`💥` is intentionally not a parseable prefix), `scripts/commit-msg.template`, `scripts/session-materialize.sh`, `scripts/uninstall-hook.sh`, `hooks/hooks.json`.

---

### Task 1: Parser test harness (red)

Add comprehensive tests for the new grammar. Most "happy path" cases for scope/bang will fail against the current parser — that's intentional, this is the red step of red→green.

**Files:**
- Create: `tests/parser.sh`
- Modify: `justfile`

- [ ] **Step 1: Write the test harness**

Create `tests/parser.sh` with this exact content:

```bash
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

next_file() { total=$((total+1)); printf '%s/msg-%d' "$scratch" "$total"; }

assert_rewrite() {
    local input="$1" expected="$2" name="$3" f
    f="$(next_file)"; printf '%s\n' "$input" > "$f"
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
    local input="$1" name="$2" f
    f="$(next_file)"; printf '%s\n' "$input" > "$f"
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
    local input="$1" want_stderr="$2" name="$3" f
    f="$(next_file)"; printf '%s\n' "$input" > "$f"
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
    local input="$1" source_type="$2" name="$3" f
    f="$(next_file)"; printf '%s\n' "$input" > "$f"
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

# Second type, for variety.
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
```

- [ ] **Step 2: Add the `test-parser` recipe and wire it into `test-integration`**

Edit `justfile`. Append a new recipe and update the existing `test-integration`:

```make
# Unit tests for scripts/gitmoji.sh: parsing/rendering of the
# Conventional Commits 1.0.0 first-line grammar.
test-parser:
    bash tests/parser.sh

# Run all integration tests.
test-integration: test-parser test-materialize test-uninstall
```

Replace the existing `test-integration: test-materialize test-uninstall` line with the version above. The new recipe goes right above it.

- [ ] **Step 3: Verify the harness runs and the new-grammar cases fail (red)**

Run: `just test-parser`

Expected: many `FAIL` lines for scope/bang cases (the current parser rejects `feat(api): msg` as an unknown prefix), and `PASS` for the cases the old parser already handles (`feat: msg`, source-type skips, `✨ ...` skip). Overall exit code 1.

This is the TDD red step. Do not proceed to Task 2 if the harness itself crashes — any errors here are bugs in the test code, not in the parser.

- [ ] **Step 4: Commit**

```bash
git add tests/parser.sh justfile
git commit -m "$(cat <<'EOF'
✅ unit tests for full conventional commit first-line grammar

Table-driven cases covering scope, breaking-change `!`, the scope
character class, the round-trip skip, every rejection branch, and the
merge/squash/amend source-type no-ops. Most new-grammar cases fail
against the current parser — Task 2 makes them pass.
EOF
)"
```

---

### Task 2: Rewrite `gitmoji.sh` for the new grammar (green)

Replace the parse/render branch with the new regex + helper. After this task, `just test-parser` is fully green and the materialize/uninstall integration tests continue to pass.

**Files:**
- Modify: `scripts/gitmoji.sh`

- [ ] **Step 1: Rewrite the script**

Replace the entire content of `scripts/gitmoji.sh` with:

```bash
#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# commit-msg hook: replace conventional commit prefix with gitmoji.
# Grammar: type[(scope)][!]: description
set -euo pipefail

BOOM='💥'

script_dir="$(cd "$(dirname "$0")" && pwd)"
msg_file="$1"
source_type="${2:-}"

# Don't modify merge, squash or amend messages
case "$source_type" in
    merge|squash|commit) exit 0 ;;
esac

# Load mapping table (set +u: declare -A incompatible with nounset)
set +u
# shellcheck source=gitmoji.cfg
source "$script_dir/gitmoji.cfg"
set -u

first_line=$(head -n 1 "$msg_file")

# If message already starts with a known emoji, leave it alone.
# Round-trip safety: a previously-rewritten "✨💥 msg" matches on "✨".
set +u
for e in "${gitmoji[@]}"; do [[ "$first_line" == "$e"* ]] && exit 0; done
set -u

list_prefixes() {
    printf '%s\n' "${!gitmoji[@]}" | sort | sed 's/^/  /'
}

re_full='^([a-z]+)(\(([a-z0-9._/-]+)\))?(!)?: (.+)$'
re_empty_scope='^[a-z]+\(\)!?: '

if [[ "$first_line" =~ $re_full ]]; then
    prefix="${BASH_REMATCH[1]}"
    # Optional groups: bash leaves their BASH_REMATCH slots as empty
    # strings; `:-` is defensive for older bash + nounset interaction.
    scope="${BASH_REMATCH[3]:-}"
    bang="${BASH_REMATCH[4]:-}"
    rest="${BASH_REMATCH[5]}"

    if [[ -v "gitmoji[$prefix]" ]]; then
        emoji="${gitmoji[$prefix]}"
        if [[ -n "$bang"  ]]; then emoji="${emoji}${BOOM}"; fi
        if [[ -n "$scope" ]]; then rest="${scope}: ${rest}"; fi
        { echo "$emoji $rest"; tail -n +2 "$msg_file"; } > "$msg_file.tmp"
        mv "$msg_file.tmp" "$msg_file"
    else
        echo "Unknown prefix '$prefix'. Valid prefixes:" >&2
        list_prefixes >&2
        exit 1
    fi
elif [[ "$first_line" =~ $re_empty_scope ]]; then
    echo "Empty scope. Scope must be non-empty. Valid prefixes:" >&2
    list_prefixes >&2
    exit 1
else
    echo "Missing or malformed conventional commit prefix." >&2
    echo "Expected: type[(scope)][!]: description" >&2
    echo "Valid prefixes:" >&2
    list_prefixes >&2
    exit 1
fi
```

Notes for the engineer:

- `BOOM` is a constant. Do not move it into `gitmoji.cfg` — it is not a parseable prefix, only an output modifier.
- `BASH_REMATCH[3]` carries the scope contents (group 2 is the parenthesised whole including `(` and `)`); `BASH_REMATCH[4]` carries `!` when present, empty otherwise.
- `(.+)` not `(.*)` for the description — a trailing-empty subject like `feat: ` must be rejected.
- The two `if [[ -n ... ]]; then ...; fi` lines deliberately don't use `&&`-shortcut form; `set -e` interacts badly with `[[ ... ]] && cmd` (shellcheck SC2015).

- [ ] **Step 2: Run shellcheck**

Run: `shellcheck -x scripts/*.sh`

Expected: no warnings. (Also exercised by `just precommit`.)

- [ ] **Step 3: Run the parser tests**

Run: `just test-parser`

Expected: every line is `PASS`, final summary `PASS: N cases`, exit code 0.

- [ ] **Step 4: Run the full integration suite**

Run: `just test-integration`

Expected: parser, materialize, and uninstall tests all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/gitmoji.sh
git commit -m "$(cat <<'EOF'
✨ parse scope and breaking-change marker in commit subjects

Extend the commit-msg hook to the full Conventional Commits 1.0.0
first-line grammar: `type[(scope)][!]: description`. Scope renders
as `<scope>: …` prepended to the description; `!` renders as 💥
appended to the type emoji. Bare `💥 msg` is rejected — users must
declare a type. `BREAKING CHANGE:` footer detection is not added.
EOF
)"
```

---

### Task 3: README — document scope and breaking-change syntax

Update the user-facing docs to show the new shapes and call out the
`!` shorthand explicitly.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the "What it does" example block**

Find the fenced block under `## What it does` that currently reads:

```
feat: add new feature    →   ✨ add new feature
fix: handle edge case    →   🐛 handle edge case
docs: update README      →   📝 update README
```

Replace it with:

```
feat: add new feature       →   ✨ add new feature
fix: handle edge case       →   🐛 handle edge case
docs: update README         →   📝 update README
feat(api): add endpoint     →   ✨ api: add endpoint
feat!: drop python 3.8      →   ✨💥 drop python 3.8
refactor(api)!: rename it   →   ♻️💥 api: rename it
```

- [ ] **Step 2: Add "Scope" and "Breaking changes" subsections**

Right after the "What it does" paragraph that ends with
"Invalid prefix or missing prefix → commit rejected with a listing of
valid prefixes." (and before the `## Installation` header), insert:

```markdown
### Scope

An optional scope in parentheses is rendered into the rewritten
subject as `<scope>: <description>`:

    feat(api): add endpoint    →   ✨ api: add endpoint
    fix(core/utils): bug       →   🐛 core/utils: bug

Scope must be lowercase: `[a-z0-9._/-]+`. Empty scope (`feat(): msg`)
is rejected.

### Breaking changes

Mark a breaking change with `!` after the type (and scope, if any). The
hook appends 💥 to the type emoji:

    feat!: drop python 3.8         →   ✨💥 drop python 3.8
    refactor(api)!: rename method  →   ♻️💥 api: rename method

This follows the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
shorthand. The `BREAKING CHANGE:` footer is **not** detected — use `!`
in the subject line to flag breaking changes. A bare emoji subject like
`💥 msg` is rejected; declare a type (`feat!: …`, `refactor!: …`, etc.)
instead.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
📝 document scope and breaking-change syntax in README

Adds "Scope" and "Breaking changes" subsections explaining
`type(scope)!: description` and the 💥 rendering, and updates the
examples block to cover all four shapes.
EOF
)"
```

---

### Task 4: DESIGN.md — update grammar and non-goals

Bring the design doc in line with the new parser.

**Files:**
- Modify: `DESIGN.md`

- [ ] **Step 1: Update the "Last updated" date**

Find the line `Last updated: 2026-05-19.` and change to `Last updated: 2026-05-20.`.

- [ ] **Step 2: Update the grammar bullet in "Safety rules"**

Find this bullet under `## Safety rules`:

```markdown
- **Lowercase-only conventional prefixes.** The regex `^([a-z]+):\ (.*)`
  is intentional. Mixed-case or dotted prefixes are rejected with a
  helpful message listing valid prefixes, not silently mangled.
```

Replace it with:

```markdown
- **Lowercase-only conventional prefixes.** The hook accepts the full
  Conventional Commits 1.0.0 first-line grammar
  `type[(scope)][!]: description`, with type matching `[a-z]+` and
  scope matching `[a-z0-9._/-]+`. Mixed-case or dotted types,
  uppercase scopes, and bare-emoji subjects (`💥 msg`) are rejected
  with a helpful message listing valid prefixes, not silently mangled.
  Empty scope (`feat(): msg`) gets a distinct error.
- **Scope rendering.** A parenthesised scope is preserved by
  prepending it to the description as `<scope>: …` in the rewritten
  subject, so reviewers don't lose it.
- **Breaking-change rendering.** The Conventional Commits `!` marker
  appends `💥` to the type emoji with no intervening space, so
  `✨💥 …` reads as a single visual token. `💥` is a script-local
  constant, not a parseable type. The `BREAKING CHANGE:` footer is
  not inspected; see Non-goals.
```

- [ ] **Step 3: Add `BREAKING CHANGE:` footer to "Non-goals"**

Find the `## Non-goals` section and append a new bullet:

```markdown
- `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer detection. The hook
  reads only the first line. Footer support is purely additive and
  could be added later without changing the first-line grammar.
```

- [ ] **Step 4: Commit**

```bash
git add DESIGN.md
git commit -m "$(cat <<'EOF'
📝 record scope and breaking-change grammar in DESIGN

Updates the "Safety rules" section with the full Conventional Commits
1.0.0 first-line grammar, adds scope-rendering and breaking-change-
rendering bullets, and lists `BREAKING CHANGE:` footer detection as
an explicit non-goal.
EOF
)"
```

---

## Out of scope (not in this plan)

- Release. The user invokes `just release <bump> --yes` as a separate step after the plan completes.
- `BREAKING CHANGE:` footer detection. Recorded as a non-goal in DESIGN.md; can land as a follow-up plan.
- Style linting (subject length, trailing period, imperative mood). Not a parser concern.
- Per-repo scope conventions. The character class is fixed at `[a-z0-9._/-]+`; users who need looser scope chars can fork.
