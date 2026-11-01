## Remaining

- `scripts/session-materialize.sh` hardcodes `$repo_root/.git/hooks`. In a linked worktree or submodule `.git` is a file, so `mkdir` fails and SessionStart exits 1 every session; with `core.hooksPath` set (husky, lefthook) it installs where git never looks and still tells the agent the hook adds the emoji. Resolving the dir with `git rev-parse --git-path hooks` fixes the first; what to do under `core.hooksPath` (install there, or take the foreign-hook branch) is a design call.

- Curate the `ddaanet` tier index from another repo: tier lines alone are ~24.5 KB, so the root `memory/MEMORY.md` (26,094 B) stays past the ~24,985 B loader cutoff and gitmoji's own facts load truncated.
