# Skipping git-authored commit messages — design

2026-07-23

## Problem

`git subtree pull --squash` generates the merge message
`Merge commit '<sha>'`. The gitmoji `commit-msg` hook rejects it
("Missing or malformed conventional commit prefix"), git reports
`Not committing merge; use 'git commit' to complete the merge`, and the
merge is left staged but uncommitted.

This is not subtree-specific. Any `git merge` with an auto-generated
message hits it, in every repo where the hook is installed.

The hook already carries a guard meant to prevent this
(`scripts/gitmoji.sh:9-14`):

```bash
source_type="${2:-}"
case "$source_type" in
    merge|squash|commit) exit 0 ;;
esac
```

It is dead code. Git passes the `commit-msg` hook exactly one argument,
so `$2` is always empty and the `case` never matches. The lines were
written to `prepare-commit-msg` semantics — that hook takes up to three
arguments — but the script is installed as `commit-msg`
(`scripts/session-materialize.sh:29`, via `scripts/commit-msg.template`,
which execs `gitmoji.sh "$@"`).

The fix belongs here rather than in any caller. Git's own auto-generated
messages are not the user's to make conventional, and the hook should
not reject them. Patching a specific caller — for instance passing
`-m "chore: …"` to `git subtree pull` from `claude-plugin-dev`'s
`release.just` — was rejected: it fixes one invocation of one command
while every ordinary `git merge` stays broken, and would need
re-propagating to every consumer that vendors the toolkit.

## What a commit-msg hook can observe

Probed empirically against git 2.47.3. Every scenario was run in a
throwaway repo with an instrumented `commit-msg` hook logging `$#`, the
basename of `$1`, `$GIT_DIR`, and the presence of each state marker.

| Operation | Hook fires? | Marker present | `$1` basename |
| --- | --- | --- | --- |
| ordinary commit | yes | — | `COMMIT_EDITMSG` |
| `git merge` (auto message) | yes | `MERGE_HEAD` | `MERGE_MSG` |
| `git subtree pull --squash` | yes | `MERGE_HEAD` | `MERGE_MSG` |
| merge completed via `git commit` (after conflict, hook rejection, or `--no-commit`) | yes | `MERGE_HEAD` | `COMMIT_EDITMSG` |
| `git merge --squash` + commit | yes | `SQUASH_MSG` | `COMMIT_EDITMSG` |
| conflicted cherry-pick → `git commit` | yes | `CHERRY_PICK_HEAD` | `COMMIT_EDITMSG` |
| conflicted revert → `git commit` | yes | `REVERT_HEAD` | `COMMIT_EDITMSG` |
| `git commit --fixup` / `--squash` / `--fixup=amend:` | yes | none | `COMMIT_EDITMSG` |
| `git rebase -i` reword | yes | none | `COMMIT_EDITMSG` |
| `git commit --amend` | yes | none | `COMMIT_EDITMSG` |
| clean `git revert` (± `--edit`) | **no** | — | — |
| clean `git cherry-pick` (± `--edit`) | **no** | — | — |
| `git rebase --continue` after conflict | **no** | — | — |

Four conclusions follow, and they determine the design:

- **`argc` is always 1.** The `case "$2"` guard is confirmed dead.
- **State markers are the robust signal.** The message-file basename is
  *not* sufficient: completing an interrupted merge passes
  `COMMIT_EDITMSG` while `MERGE_HEAD` is still present. That case —
  which is exactly what a user does after the hook rejects a merge — is
  the one basename detection would miss.
- **`GIT_DIR` is unset inside the hook.** The git dir must come from
  `git rev-parse --git-dir`.
- **Clean revert, clean cherry-pick, and `rebase --continue` never
  reach the hook at all**, so they need no handling. `--amend` and
  rebase `reword` do reach it, but are passed the commit's existing
  message, which in an installed repo already carries an emoji and so
  exits via the existing round-trip check.

A second probe confirmed no marker lingers past the operation that
created it: `MERGE_HEAD`, `SQUASH_MSG`, `CHERRY_PICK_HEAD` and
`REVERT_HEAD` are all cleared by the commit that ends the operation and
by the corresponding `--abort`. Marker-based detection therefore cannot
silently disable the hook for later commits.

## Design

### Detection

Skip when either condition holds:

1. Any of `MERGE_HEAD`, `SQUASH_MSG`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`
   exists in the git dir.
2. The first line matches `^(fixup|squash|amend)! ` — git's autosquash
   subjects, which carry no marker but are equally git's to author.

One rule, stated two ways because the evidence supports no single
signal: *git wrote this message, so it is not ours to rewrite.*

Rejected alternatives: message-file basename (insufficient, per above);
a `^Merge ` message pattern (fragile, and would silence a legitimate
user subject that happens to start with the word).

### Behaviour on detection

Exit 0, leaving the message byte-for-byte as git wrote it. No emoji is
prepended — decorating merges with `🔀` would add a second rewrite path
needing its own round-trip guard, and would mutate a message git owns.
This matches DESIGN.md's long-stated intent that the plugin "never
corrupts merge commit messages".

### Placement

In `scripts/gitmoji.sh`, replacing the dead `source_type` lines. The
per-repo `commit-msg.template` wrapper stays a three-line `exec`.

Rejected alternatives: gating inside the wrapper, or having the wrapper
synthesize a `source_type` argument to revive the existing `case`. Both
put the logic in the file that is copied verbatim into `.git/hooks/`,
where `just test` and `tests/parser.sh` bypass it entirely — the check
would be untested by the unit suite, and stale copies would persist in
every repo until the next SessionStart.

### Shape

```bash
msg_file="$1"
first_line=$(head -n 1 "$msg_file")

# Git-authored messages are not ours to rewrite. A state marker in the
# git dir means an in-progress merge/squash/cherry-pick/revert is being
# committed; the message came from git, not the user.
git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -n "$git_dir" ]]; then
    for m in MERGE_HEAD SQUASH_MSG CHERRY_PICK_HEAD REVERT_HEAD; do
        [[ -e "$git_dir/$m" ]] && exit 0
    done
fi

# Autosquash subjects carry no marker but are equally git's.
re_autosquash='^(fixup|squash|amend)! '
[[ "$first_line" =~ $re_autosquash ]] && exit 0
```

Details that matter:

- `|| true` keeps `set -e` satisfied when the hook runs outside a repo,
  which is what `just test` does.
- `git rev-parse --git-dir` returns a path relative to cwd (`.git`), and
  cwd is the repo root during a hook, so `"$git_dir/$m"` resolves. In a
  linked worktree it returns that worktree's gitdir, which is where the
  markers live.
- `[[ … ]] && exit 0` inside a `for` under `set -euo pipefail` is safe —
  the failing test is not the command following the final `&&`, so it is
  exempt from `set -e`. This is already the idiom at `gitmoji.sh:27`.
- `re_autosquash` is a variable, matching the existing `re_full` /
  `re_empty_scope` style and avoiding an escaped literal space.
- `first_line` moves above the guard so both skips form one block. The
  mapping table is sourced afterwards; neither skip needs it.

## Testing

Split by what each suite can observe.

### `tests/parser.sh`

The autosquash skip is first-line parsing, so it belongs in the existing
unit suite:

- `assert_skip` for `fixup! feat: x`, `squash! feat: x`, `amend! feat: x`
- `assert_reject` for `fixup!x` (no space), confirming the regex is not
  over-broad

**Isolation change.** parser.sh currently creates its scratch dir inside
the plugin root and invokes the hook with cwd inside the gitmoji repo,
so the new marker guard would read *ambient* repo state. Running
`just test-parser` while gitmoji itself is mid-merge would make every
test pass as a silent skip. To avoid shipping a second bug that is
invisible to its own tests, parser.sh's scratch dir moves to `mktemp -d`
under the system temp, and hook invocations run with cwd set there — no
enclosing repo, deterministic result. Nothing else about the suite
changes.

### `tests/git-states.sh` (new)

The marker guard can only be exercised against real git. This suite
builds throwaway repos and points `core.hooksPath` at a directory
holding `commit-msg.template`, `gitmoji.sh` and `gitmoji.cfg` together,
so the wrapper gets integration coverage as a side effect.

Assertions — message must survive verbatim and the command must exit 0:

- plain `git merge --no-edit` → `Merge branch 'side'`
- a merge whose message is `Merge commit '<sha>'` — the reported
  `subtree pull --squash` shape
- conflicted merge → resolve → `git commit` (the case basename
  detection would miss)
- `git merge --squash` + commit → `Squashed commit of the following:`
- conflicted cherry-pick → `git commit`
- conflicted revert → `git commit`
- `git commit --fixup HEAD` → `fixup! …`

Negative assertions, guarding against over-skipping:

- an ordinary commit in the same repo is still rewritten
- the commit *immediately after* a completed merge is still rewritten,
  locking in the no-lingering-marker finding

Wired as `just test-git-states` and added to `test-integration`'s
dependency list.

### Gates

Unchanged: `just precommit` (which runs
`shellcheck -x scripts/*.sh tests/*.sh`, so the new suite must be
shellcheck-clean) and `just test-integration`. `just prerelease` is
exactly `precommit`.

## Documentation updates

Three places describe the current, wrong behaviour:

- **`DESIGN.md`** — the safety rule "Merge/squash/amend skipping"
  describes the dead `source_type` mechanism. Rewrite it as
  git-authored-message skipping: name the four markers and the
  autosquash prefixes, and record that clean `revert` / `cherry-pick` /
  `rebase --continue` never invoke the hook (so need no handling), while
  `--amend` and rebase `reword` are covered by the existing emoji
  round-trip. Bump `Last updated`.
- **`CLAUDE.md`** — the line "The hook must remain a no-op for merge,
  squash, and amend commits (`source_type` of `merge`, `squash`,
  `commit`)" is a description of the dead code. Replace it.
- **`justfile`** — add a one-line doc comment for `test-git-states`
  alongside the existing test-recipe notes in the header block.

The untracked `brief-merge-commit-messages.md` at the repo root is
superseded by this spec and is deleted rather than committed.

## Non-goals

- Emoji-decorating merge, revert, or cherry-pick messages.
- Handling clean `revert` / `cherry-pick` / `rebase --continue` — they
  never invoke the `commit-msg` hook.
- Reading `BREAKING CHANGE:` footers; unchanged from the existing
  non-goals.
- Any change to `commit-msg.template`, `session-materialize.sh`, or
  `uninstall-hook.sh`.

## Constraints

- Bash, shellcheck-clean.
- Do not hand-edit `plugin-dev/` — it is a vendored git subtree.
  Changes there go to `ddaanet/claude-plugin-dev`, get released, then
  pulled.
- Round-trip safety must not regress: a message already starting with a
  known emoji exits 0 (`gitmoji.sh:24-28`).
