# Agent Instructions — gitmoji plugin

Plugin development conventions. Applies when working inside this repo to
edit the hook scripts, installer, or commands.

## Layout

- `.claude-plugin/plugin.json` — manifest
- `commands/install.md` — slash command `/gitmoji:install`
- `commands/uninstall.md` — slash command `/gitmoji:uninstall`
- `scripts/gitmoji.sh` — the commit-msg hook body (stowed verbatim into
  the target repo's `.git/hooks/` by the installer)
- `scripts/gitmoji.cfg` — prefix → emoji mapping (bash associative
  array, sourced by `gitmoji.sh`)
- `scripts/install-hook.sh` — installer; copies the hook scripts into
  `.git/hooks/` and writes a `commit-msg` wrapper
- `scripts/uninstall-hook.sh` — removes only files marked as installed
  by this plugin

## Conventions

- The installer must be idempotent with the plugin-installed marker
  (`gitmoji-plugin-installed` comment in the `commit-msg` wrapper). Do
  not overwrite hooks without the marker.
- `gitmoji.sh` and `gitmoji.cfg` are lifted from `scripts/` in the
  `devddaanet` repo. Upstream source of truth is this plugin now — any
  change should happen here and be tested via `just test`.
- The hook must remain a no-op for merge, squash, and amend commits
  (`source_type` of `merge`, `squash`, `commit`).
- Prefix extraction regex: `^([a-z]+):\ (.*)`. Lowercase-only by design.

## Testing

- `just test` — runs the hook against a sample commit message.
- `just test msg="docs: update readme"` — custom message.
- `just install-local` / `just uninstall-local` — install/uninstall in
  the current repo for live testing.

## Non-goals

- Custom mappings per repo. The mapping is a single file; fork or patch
  `gitmoji.cfg` if needed.
- Non-conventional prefix styles (uppercase, dot-separated, etc.).
  Conventional commits are explicitly the contract.
- A pre-commit hook variant. Only `commit-msg` is supported — it's the
  correct event for message rewriting.
