## Open decisions

- Keep or drop `starts_with_emoji` in `scripts/gitmoji.sh` (dedicated emoji-led rejection vs folding its act sentence into the generic rejection). Pending a session-log analysis of the commit-message formats agents write. The xhigh review's detector findings (emoji after the prefix, `⏪` outside the byte range, false positives on `✓`/math letters, the four-process byte read, no design.md entry) wait on this call.

## Remaining

- Release gitmoji 0.6.0 (`just release minor`, run or approved by my human partner). `origin/main` carries a pre-amend copy of the `dev` tip that is not an ancestor of `dev`, so moving `origin/main` to the release needs a force-push; `just release` alone fails at the push, leaving the commit and tag local. Review state of `dev` against `main`: simplify, xhigh `/code-review` and Codex adversarial review done; the medium pass on the xhigh fixes is not yet run.
- `scripts/session-materialize.sh` hardcodes `$repo_root/.git/hooks`. In a linked worktree or submodule `.git` is a file, so `mkdir` fails and SessionStart exits 1 every session; with `core.hooksPath` set (husky, lefthook) it installs where git never looks and still tells the agent the hook adds the emoji. Resolving the dir with `git rev-parse --git-path hooks` fixes the first but also follows `core.hooksPath`, so the two halves are one design call: install there, or take the foreign-hook branch.
