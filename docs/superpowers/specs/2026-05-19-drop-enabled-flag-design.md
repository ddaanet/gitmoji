# Drop the `pluginConfigs.options.enabled` flag

2026-05-19

## Context

The current design uses a bespoke per-repo flag
`pluginConfigs["gitmoji@ddaanet"].options.enabled` (in
`.claude/settings.json`) as the opt-in signal. The SessionStart hook
parses settings precedence, materializes `.git/hooks/commit-msg` if
the flag resolves true, tears it down if false. Slash commands
`/gitmoji:install` and `/gitmoji:uninstall` toggle the flag via the
harness Edit/Write tools.

Two problems converged:

1. Claude Code's auto-mode classifier now hard-blocks agent
   Edit/Write on `.claude/settings.json`, even with explicit user
   authorization. The `/gitmoji:install` slash command therefore
   cannot perform its job — users have to hand-edit settings.json.
   Observed repeatably while installing in `/Users/david/code/handoff`.
2. The bespoke flag duplicates `enabledPlugins`, Claude Code's
   native plugin-enable mechanism. The custom flag was reaching
   outside its lane and re-implementing precedence resolution in
   shell.

## Decision

Drop the `pluginConfigs.options.enabled` flag entirely. Lean on
`enabledPlugins["gitmoji@ddaanet"]` as the sole opt-in. Collapse
the plugin's surface to a SessionStart hook + materializer +
single `/gitmoji:uninstall` cleanup command.

Semantics shift from opt-in-per-repo (with ambient slash commands)
to one-lever-per-scope: enabling the plugin in a scope enables
both the slash command(s) and commit-msg rewriting in that scope.
The previous two-lever model was solving a problem the user does
not actually have.

## Architecture

One lever: `enabledPlugins["gitmoji@ddaanet"]`, resolved through
Claude Code's standard scope chain. More specific wins:

1. `.claude/settings.local.json` (repo, per-user, gitignored)
2. `.claude/settings.json` (repo, checked in)
3. `~/.claude/settings.json` (user)

The plugin owns no opt-in flag of its own. Three operational shapes
fall out:

- **User scope enabled** (`~/.claude/settings.json`
  `enabledPlugins["gitmoji@ddaanet"] = true`): plugin loaded in
  every repo. SessionStart fires; hook materialized everywhere. Per-
  repo opt-out via `enabledPlugins = false` in
  `.claude/settings.local.json` or `.claude/settings.json`.
- **Project scope enabled** (`.claude/settings.json` checked in with
  `enabledPlugins["gitmoji@ddaanet"] = true`): plugin loaded in this
  repo for everyone who clones. SessionStart fires; hook
  materialized. Auto-install-on-clone works without any explicit
  per-clone step from teammates.
- **Plugin not enabled in scope**: SessionStart doesn't fire. Any
  hook materialized in a previous session persists in `.git/hooks/`
  until manually removed (see asymmetry below).

`enabledPlugins` is owned by Claude Code and managed by the user
via `/plugin install`, `/plugin uninstall`, the `/plugins` TUI, or
direct hand-edit of `.claude/settings.json`. The plugin never
writes this key — that's the user's job.

The materializer's job collapses: when it runs, install or refresh
unconditionally. No flag read, no jq dependency, no teardown
branch. SessionStart becomes a pure idempotent install/refresh.

## The disable/uninstall asymmetry

Plugin install is implicit (SessionStart side-effect of being
enabled). Plugin disable/uninstall has no counterpart event — when
the plugin stops being loaded, no plugin code runs to clean up.
The hook files in `.git/hooks/` therefore persist after a `/plugin
uninstall` or scope-level disable, and git keeps running them.

This is structural, not a bug introduced by this redesign — any
SessionStart-driven materialization has the same property. Three
options were considered:

1. Accept the asymmetry; provide an explicit cleanup command.
2. Make the commit-msg wrapper self-check `enabledPlugins` by
   parsing settings.json at commit time. Rejected: only catches
   explicit `false` (not uninstall, where the key is removed), adds
   jq to the commit hot path, and pushes settings-precedence logic
   into a shell hook running outside Claude Code.
3. Switch to a two-lever model where install/uninstall are
   user-explicit commands. Rejected: loses auto-install-on-clone,
   which is the main reason to use `enabledPlugins` as the opt-in.

Chosen: (1). The plugin ships a `/gitmoji:uninstall` slash
command whose only job is to remove the materialized hook files
from the current repo, guarded by the
`gitmoji-plugin-installed` marker. Users are documented to run
this before disabling/uninstalling the plugin. There is no
matching `/gitmoji:install` — install is automatic — and the
asymmetry is intentional: it reflects what's actually true about
the architecture.

The orphaning case (user uninstalls plugin without running
cleanup first) degrades gracefully: the hook keeps rewriting
conventional prefixes to gitmoji, which is exactly what the user
opted in to. They can `rm .git/hooks/{commit-msg, gitmoji.sh,
gitmoji.cfg}` to finish cleanup. README documents both paths.

## Component changes

### Delete

- `commands/install.md` — no opt-in for the plugin to write; the
  user enables via `/plugin install` or hand-edit.
- `scripts/install-hook.sh` — same reason.

### Modify

- `scripts/session-materialize.sh` — strip the jq settings-resolution
  block. Becomes: resolve repo root via `${CLAUDE_PROJECT_DIR}`;
  exit if not in a git repo; if `.git/hooks/commit-msg` exists
  without the marker, warn and exit; otherwise copy `gitmoji.sh`,
  `gitmoji.cfg`, and `commit-msg.template` into `.git/hooks/` and
  `chmod +x`. Idempotent. Approximately 20 lines, no jq, no
  teardown branch.
- `scripts/uninstall-hook.sh` — strip settings.json mutation.
  Becomes: resolve repo root; if `.git/hooks/commit-msg` exists
  and carries the marker, `rm` the three hook files. No jq.
  Runnable from any shell, including after the plugin has been
  disabled (cache lingers until the user clears it).
- `commands/uninstall.md` — rewrite. Body shells to `bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh` with
  `dangerouslyDisableSandbox: true` (per memory, this is auto-
  approved for plugin scripts writing to `.git/hooks/`). No more
  Edit/Write of settings.json.
- `hooks/hooks.json` — update the `description` field to remove the
  "driven by the effective …enabled setting" language; replace with
  language reflecting the always-install-when-fired semantics.
- `.claude-plugin/plugin.json` — refresh `description` to drop the
  "Ships an installer command" phrasing. The plugin ships a single
  cleanup command, not an installer.
- `CLAUDE.md` — replace the "Opt-in model" section to describe
  `enabledPlugins` as the source of truth. Drop the "settings path:
  pluginConfigs slot" paragraph. Drop `commands/install.md` and
  `scripts/install-hook.sh` from "Layout". Add a short paragraph
  on the cleanup command and the disable asymmetry. Update
  "Conventions" to reflect that the materializer no longer reads a
  flag and no longer tears down.
- `DESIGN.md` — substantial rewrite of "Opt-in model",
  "Materialization", and "Decomposition" sections. Delete the
  whole "Why slash commands do not invoke the bash scripts"
  section — moot, since the one remaining slash command does shell
  out. Add a section on the disable/uninstall asymmetry mirroring
  this spec. Keep "Safety rules", "Relationship to upstream
  devddaanet", "Non-goals" essentially intact. Rewrite
  "Dependencies": jq is removed from the runtime path entirely
  (materializer no longer parses settings; uninstall-hook.sh no
  longer edits settings); it remains used only by the justfile for
  JSON validation in `just check`. Document this shift explicitly.

### Keep unchanged

- `scripts/gitmoji.sh` — commit-msg hook body.
- `scripts/gitmoji.cfg` — prefix → emoji mapping.
- `scripts/commit-msg.template` — marker-bearing wrapper.
- `hooks/hooks.json` SessionStart registration (only the
  `description` field changes).

## Migration

The behavior shift affects existing users who have the plugin
enabled at user scope and rely on per-repo
`pluginConfigs["gitmoji@ddaanet"].options.enabled = false` to keep
the hook off in specific repos. After upgrading, that flag is
silently ignored and the hook will be materialized on the next
SessionStart in those repos.

Mitigations:

- CHANGELOG / release notes call this out. Recommend
  `enabledPlugins["gitmoji@ddaanet"] = false` in those repos'
  `.claude/settings.local.json` (or `.claude/settings.json`) to
  preserve previous behavior.
- Stale `pluginConfigs["gitmoji@ddaanet"]` entries in users'
  settings.json files are harmless — Claude Code's validator
  accepts the slot; the plugin no longer reads it. No automated
  migration. Users may delete the entries at their leisure.
- Version bump: 0.2.3 → 0.3.0. Breaking change in opt-in
  semantics warrants a minor bump.

## Documentation

README (or equivalent user-facing docs) needs:

- One-paragraph statement of the model: enable the plugin
  (`/plugin install gitmoji@ddaanet`); the hook is materialized in
  every repo on first session. To enable only in specific repos,
  set `enabledPlugins["gitmoji@ddaanet"] = true` in each repo's
  `.claude/settings.json` and either don't enable user-scope or set
  user-scope to `false`. To opt a single repo out, use
  `enabledPlugins["gitmoji@ddaanet"] = false` in
  `.claude/settings.local.json`.
- Explicit warning: before `/plugin uninstall gitmoji@ddaanet`,
  run `/gitmoji:uninstall` in each opted-in repo to clean up the
  persistent `.git/hooks/` files. If you've already uninstalled,
  `rm .git/hooks/{commit-msg, gitmoji.sh, gitmoji.cfg}` works as a
  fallback (with the caveat that it skips the marker check, so
  only do this if you're certain those files came from gitmoji).

## Non-goals (unchanged from current design)

- Custom per-repo emoji mappings.
- Non-conventional prefix styles.
- A pre-commit hook variant.
- Globally-enabled-but-per-repo-inactive split (the previous
  two-lever model). Collapsed into the one-lever
  `enabledPlugins` model.
