# Agent Instructions — gitmoji plugin

Plugin development conventions. Applies when working inside this repo
to edit the hook scripts, installer, or commands.

## Layout

- `.claude-plugin/plugin.json` — manifest
- `commands/install.md` — slash command `/gitmoji:install`
- `commands/uninstall.md` — slash command `/gitmoji:uninstall`
- `hooks/hooks.json` — SessionStart hook that runs
  `session-materialize.sh`
- `scripts/gitmoji.sh` — commit-msg hook body (copied per-repo into
  `.git/hooks/` by the materializer)
- `scripts/gitmoji.cfg` — prefix → emoji mapping (bash associative
  array, sourced by `gitmoji.sh`)
- `scripts/session-materialize.sh` — reads `gitmoji.enabled` from the
  settings hierarchy and materializes or tears down the per-repo hook
- `scripts/install-hook.sh` — writes `gitmoji.enabled = true` into
  project-scope `.claude/settings.json` and invokes the materializer
- `scripts/uninstall-hook.sh` — writes `gitmoji.enabled = false` and
  invokes the materializer

## Opt-in model

Opt-in is a **settings.json entry**, not the presence of a file in
`.git/hooks/`. The effective value of `gitmoji.enabled` is read across
the standard Claude Code hierarchy (more specific wins):

1. `.claude/settings.local.json` (repo, per-user, gitignored)
2. `.claude/settings.json` (repo, checked in)
3. `~/.claude/settings.json` (user)

The per-repo `.git/hooks/` files are a **cache**, not the source of
truth — they are regenerated on every SessionStart from the plugin
version running in that session.

## Conventions

- `session-materialize.sh` is the single entry point that writes or
  removes per-repo hook files. The installer and uninstaller both
  delegate to it; SessionStart invokes it directly.
- The per-repo `commit-msg` wrapper must carry the
  `gitmoji-plugin-installed` marker. The materializer refuses to
  overwrite a `commit-msg` without the marker (so unrelated user hooks
  stay intact), and removes files only when the marker is present.
- `gitmoji.sh` and `gitmoji.cfg` are lifted from `scripts/` in the
  `devddaanet` repo. Upstream source of truth is this plugin now — any
  change should happen here and be tested via `just test`.
- The hook must remain a no-op for merge, squash, and amend commits
  (`source_type` of `merge`, `squash`, `commit`).
- Prefix extraction regex: `^([a-z]+):\ (.*)`. Lowercase-only by design.
- `jq` is a hard dependency of the installer, uninstaller, and
  materializer (used to read and edit settings JSON). Fail with a clear
  error if missing.

## Testing

- `just test` — runs the hook against a sample commit message.
- `just test msg="docs: update readme"` — custom message.
- `just materialize` — runs the SessionStart materializer against the
  current repo (useful for iterating on `session-materialize.sh`).
- `just install` / `just uninstall` — install/uninstall in the current
  repo for live testing.

## Non-goals

- Custom mappings per repo. The mapping is a single file; fork or patch
  `gitmoji.cfg` if needed.
- Non-conventional prefix styles (uppercase, dot-separated, etc.).
  Conventional commits are explicitly the contract.
- A pre-commit hook variant. Only `commit-msg` is supported — it's the
  correct event for message rewriting.
