## Open decisions

- How `main` reaches the release: local `main` was reset to v0.5.2 while `origin/main` still points at the `dev` tip 9e7883f, and `origin` has no `dev` branch. Either force-push `main` back to v0.5.2 and push `dev`, then release from `main` after it moves to `dev`; or leave `origin/main` as is. Shared rule: a release is a review of `dev` against `main`, after which `main` moves to the release.

## Remaining

- Release gitmoji 0.6.0 (`just release minor`, run or approved by my human partner).
- `scripts/session-materialize.sh` hardcodes `$repo_root/.git/hooks`. In a linked worktree or submodule `.git` is a file, so `mkdir` fails and SessionStart exits 1 every session; with `core.hooksPath` set (husky, lefthook) it installs where git never looks and still tells the agent the hook adds the emoji. Resolving the dir with `git rev-parse --git-path hooks` fixes the first; what to do under `core.hooksPath` (install there, or take the foreign-hook branch) is a design call.
