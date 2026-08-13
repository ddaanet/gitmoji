# Conventional commit parser — design

Date: 2026-05-20.

## Problem

The commit-msg hook currently accepts only the simplest form of a
conventional commit subject line: `type: description`. The
[Conventional Commits 1.0.0 spec](https://www.conventionalcommits.org/en/v1.0.0/)
also allows an optional scope and a `!` marker for breaking changes:

```
type[(scope)][!]: description
```

Anyone who writes `feat(api): …` or `feat!: …` today gets their
commit rejected with "Unknown prefix 'feat(api)'" or similar
nonsense. The fix is to teach the parser the full first-line
grammar and render scope and breaking-change information into the
rewritten subject line.

## Grammar

The hook accepts exactly this shape on the first line:

```
type[(scope)][!]: description
```

- **`type`** — `[a-z]+`. Must be a key in `gitmoji.cfg`. Unchanged
  from today.
- **`scope`** — optional. If present, parenthesised, matching
  `[a-z0-9._/-]+`. Non-empty. Lowercase-only, mirroring the type
  rule and the project's "lowercase-only conventional prefixes"
  safety guarantee.
- **`!`** — optional. Placed between `)` and `:` when a scope is
  present; otherwise between `type` and `:`. Marks a breaking
  change per the spec.
- **`:` + single space + `description`** — literal colon, single
  literal space, then the rest of the line (non-empty).

Anything else on the first line is rejected.

### Non-goals (intentionally outside the grammar)

- **`BREAKING CHANGE:` / `BREAKING-CHANGE:` footer detection.** The
  hook reads only the first line. Detecting footers would require
  scanning the body, which we can add later without breaking
  this design — `!` and the footer carry the same meaning per the
  spec, so footer support is purely additive.
- **Style linting.** Subject length, trailing period, imperative
  mood, lowercase description — not enforced. Out of scope.
- **Uppercase / dotted / mixed-case types or scopes.** Lowercase
  only, as today.

## Rendering

| Input | Output |
|---|---|
| `feat: msg` | `✨ msg` |
| `feat!: msg` | `✨💥 msg` |
| `feat(api): msg` | `✨ api: msg` |
| `feat(api)!: msg` | `✨💥 api: msg` |

Rules:

- Type emoji always comes first.
- When `!` is present, append `💥` to the type emoji with no
  intervening space, so `✨💥` reads as a single visual token.
- When a scope is present, prepend it to the description as
  `<scope>: `. This preserves the scope information in the
  rewritten line without inventing new syntax — readers already
  understand `area: thing` style.
- Lines past the first are untouched.

`💥` lives in the script as a single constant, not in
`gitmoji.cfg`. It is a modifier, not a parseable type.

## Already-emoji skip (re-run safety)

Unchanged from today. The hook skips a first line that starts with
any value from `gitmoji.cfg`. Consequences for the new grammar:

- `✨💥 msg` (round-tripped after a previous rewrite) starts with
  `✨` → skipped. Re-runs are idempotent.
- `💥 msg` (bare boom, no type) is **not** skipped. `💥` is
  intentionally not in `gitmoji.cfg`, so this falls into the
  regex, fails to match, and is rejected. Users must write
  `feat!: msg`, not bypass with a bare emoji.

## Errors

Three failure modes. Each rejects the commit and prints a sorted
list of valid prefixes, matching the existing UX.

1. **Unknown type** — `xyz: msg` →
   `Unknown prefix 'xyz'. Valid prefixes:` + listing.
2. **Empty scope** — `feat(): msg` →
   `Empty scope in 'feat()'. Scope must be non-empty.` + listing.
3. **Syntax mismatch** — `feat:msg`, `Feat: msg`, `feat msg`,
   `feat(BAD): msg`, etc. →
   `Missing or malformed conventional commit prefix. Expected: type[(scope)][!]: description` + listing.

No further linting — the parser only validates structure.

## Implementation sketch

A single bash regex with optional groups. Description is `.+`,
not `.*`, so a trailing-empty subject (`feat: `) is rejected.
Store the pattern in a variable to keep the `[[ =~ ]]` clean:

```bash
BOOM='💥'
re='^([a-z]+)(\(([a-z0-9._/-]+)\))?(!)?: (.+)$'
if [[ "$first_line" =~ $re ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"   # empty if scope group absent
    bang="${BASH_REMATCH[4]}"    # "!" if present, else empty
    desc="${BASH_REMATCH[5]}"
    ...
fi
```

The main regex fails on `feat(): msg` (the inner group requires
at least one scope character). Before falling through to the
generic "malformed" error, a second regex —
`^[a-z]+\(\)!?: ` — is tried so we can emit the more specific
empty-scope message.

Construction of the output:

```bash
emoji="${gitmoji[$type]}"
[[ -n "$bang" ]]  && emoji="${emoji}${BOOM}"
[[ -n "$scope" ]] && desc="${scope}: ${desc}"
echo "$emoji $desc"
```

`shellcheck -x` must still pass.

## Files touched

- **`scripts/gitmoji.sh`** — new regex, scope/bang extraction,
  new error branches, single `BOOM='💥'` constant. Same shape as
  today, no new dependencies.
- **`scripts/gitmoji.cfg`** — unchanged. `💥` is deliberately
  not added.
- **`scripts/commit-msg.template`** — unchanged.
- **`README.md`** — replace the examples block with a table
  covering scope and `!`; add a "Breaking changes" subsection
  noting that `BREAKING CHANGE:` footer is not detected.
- **`DESIGN.md`** — extend the "Safety rules" section to spell
  out the new grammar; record `BREAKING CHANGE:` footer as a
  non-goal for now.
- **`tests/parser.sh`** *(new)* — table-driven cases covering:
  - happy path: all four input shapes from the rendering table,
    once for each of two representative types.
  - already-emoji skip: `✨ msg`, `✨💥 msg` pass through
    unchanged.
  - bare-boom rejection: `💥 msg` rejected.
  - unknown type, empty scope, syntax mismatch — each error
    branch fires with the expected fragment in stderr.
  - merge / squash / amend source types still no-op.
- **`justfile`** — new `test-parser` recipe (mirrors
  `test-materialize` / `test-uninstall`); added to
  `test-integration`.

## Requirements this design meets

- **Spec-faithful first line.** All four shapes from the
  Conventional Commits 1.0.0 spec parse and render.
- **Lossless scope.** Scope appears in the rewritten subject as
  `scope: …`, so reviewers don't lose it.
- **Visible breaking change.** `💥` adjacent to the type emoji is
  hard to miss on a commit list.
- **Idempotent.** Re-running the hook on its own output is still a
  no-op, via the unchanged already-emoji skip.
- **No bypass.** Bare `💥 msg` is rejected; users must declare a
  type.
- **No new dependencies.** Pure bash; `shellcheck -x` clean.
