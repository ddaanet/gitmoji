# Agent Instructions — gitmoji plugin

Plugin development conventions. Applies when working inside this
repo to edit the hook scripts, materializer, or commands.

## Layout

- `.claude-plugin/plugin.json` — manifest
- `commands/uninstall.md` — slash command `/gitmoji:uninstall`
  (the only user-visible verb; install is implicit via SessionStart)
- `hooks/hooks.json` — SessionStart hook that runs
  `session-materialize.sh`
- `scripts/gitmoji.sh` — commit-msg hook body (copied per-repo into
  `.git/hooks/` by the materializer)
- `scripts/gitmoji.cfg` — prefix → emoji mapping (bash associative
  array, sourced by `gitmoji.sh`)
- `scripts/commit-msg.template` — marker-tagged wrapper, copied
  verbatim into `.git/hooks/commit-msg`
- `scripts/session-materialize.sh` — runs on every SessionStart;
  installs/refreshes the per-repo hook files unconditionally
- `scripts/uninstall-hook.sh` — removes the marker-tagged hook
  files; backs `/gitmoji:uninstall` and `just uninstall`
- `tests/parser.sh` / `materialize.sh` / `uninstall.sh` — test
  harnesses driven by the `just test-*` recipes
- `DESIGN.md` — living rationale for design decisions; update when
  design choices change

## Opt-in model

Opt-in is `enabledPlugins["gitmoji@ddaanet"]` in
`.claude/settings.json` (any scope), resolved through Claude Code's
standard scope chain (more specific wins):

1. `.claude/settings.local.json` (repo, per-user, gitignored)
2. `.claude/settings.json` (repo, checked in)
3. `~/.claude/settings.json` (user)

This key is owned by Claude Code, not the plugin. Users toggle it
via `/plugin install`, `/plugin uninstall`, the `/plugins` TUI, or
direct hand-edit of `.claude/settings.json`. The plugin's scripts
**never** write `enabledPlugins`.

The per-repo `.git/hooks/` files are a cache, regenerated on every
SessionStart from the plugin version running in that session. The
plugin owns no opt-in flag of its own.

### The disable/uninstall asymmetry

Plugin install is implicit: SessionStart fires when the plugin is
loaded, and the materializer installs the hook. Plugin disable has
no counterpart event — when the plugin stops being loaded, no
plugin code runs to clean up. The hook files persist in
`.git/hooks/` until something explicitly removes them.

The plugin therefore ships `/gitmoji:uninstall` (slash command) and
the equivalent `bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh`
shell entry point. Users are documented to run one of these
**before** disabling or uninstalling the plugin.

## Conventions

- `session-materialize.sh` always installs/refreshes when it runs.
  Never tears down, never reads any settings key. If it runs, the
  plugin is enabled here.
- The per-repo `commit-msg` wrapper must carry the
  `gitmoji-plugin-installed` marker. The materializer refuses to
  overwrite a `commit-msg` without the marker; the uninstaller
  refuses to remove one without it.
- `gitmoji.sh` and `gitmoji.cfg` originated in `devddaanet/scripts/`;
  this plugin is the source of truth now. Changes happen here and
  are tested via `just test`.
- The hook must remain a no-op for messages git composed itself:
  a `MERGE_HEAD` / `SQUASH_MSG` / `CHERRY_PICK_HEAD` / `REVERT_HEAD`
  marker in `$(git rev-parse --git-dir)`, or a `fixup! ` / `squash! ` /
  `amend! ` first line. Git passes `commit-msg` exactly one argument,
  so there is no source-type parameter to test — see `DESIGN.md` →
  "Git-authored message skipping". Covered by `just test-git-states`.
- First-line grammar: `type[(scope)][!]: description`, with type
  `[a-z]+` and scope `[a-z0-9._/-]+`. Lowercase-only by design.
  Canonical statement and rendering rules: `DESIGN.md` →
  "Lowercase-only conventional prefixes" / "Scope rendering" /
  "Breaking-change rendering".
- `jq` is **not** a runtime dependency. It is used only by
  `just precommit` to validate manifest JSON.

## Testing

- `just test` — runs the hook against a sample commit message.
- `just test msg="docs: update readme"` — custom message.
- `just materialize` — runs the SessionStart materializer against
  the current repo (dev loop for `session-materialize.sh`).
- `just uninstall` — runs the cleanup script against the current
  repo (dev loop for `uninstall-hook.sh`).
- `just test-parser` — unit tests for `scripts/gitmoji.sh` parsing
  and rendering (Conventional Commits 1.0.0 first-line grammar).
- `just test-materialize` / `just test-uninstall` /
  `just test-integration` — `test-integration` runs the parser
  unit tests plus the materializer/uninstaller integration suites.

## Non-goals

- Custom mappings per repo. The mapping is a single file; fork or
  patch `gitmoji.cfg` if needed.
- Non-conventional prefix styles (uppercase, dot-separated, etc.).
  Conventional commits are explicitly the contract.
- A pre-commit hook variant. Only `commit-msg` is supported — it's
  the correct event for message rewriting.
- A plugin-owned opt-in flag. `enabledPlugins` is the only opt-in;
  the plugin does not introduce a parallel surface.
