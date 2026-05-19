# gitmoji — Design

Living document. Captures the research, analysis, and decisions behind
this plugin. Updated as the design evolves.

Last updated: 2026-05-19.

## Problem

The `devddaanet` repo has a commit-msg hook (`scripts/gitmoji.sh` +
`scripts/gitmoji.cfg`) installed via `just install`. It's useful outside
that repo too. Packaging it as a standalone plugin lets any Claude Code
user install it in their own repos without cloning `devddaanet`.

## Analysis — why a plugin and not a gist / standalone script

A plugin gets:

- Distribution via the `ddaanet` marketplace (discoverable, versioned)
- A SessionStart hook we can use to keep per-repo state in sync with the
  plugin version
- Clean coupling between the hook scripts and the materializer (same
  repo, `${CLAUDE_PLUGIN_ROOT}` resolves at runtime)
- Uninstall path with an explicit marker

What it does *not* need:

- A skill. The action is user-triggered setup; a slash command is the
  simpler fit.

## Opt-in model

Opt-in is `enabledPlugins["gitmoji@ddaanet"]`, resolved through
Claude Code's standard scope chain (more specific wins):

1. `.claude/settings.local.json` (repo, per-user, gitignored)
2. `.claude/settings.json` (repo, checked in)
3. `~/.claude/settings.json` (user)

This key is owned by Claude Code, not the plugin. Users toggle it
via `/plugin install`, the `/plugins` TUI, or hand-edit of
`.claude/settings.json`. The plugin's scripts never write this key
— that's the user's job.

Three operational shapes fall out:

- **User scope enabled** (`~/.claude/settings.json`
  `enabledPlugins["gitmoji@ddaanet"] = true`): plugin loaded in
  every repo. SessionStart fires; hook materialized everywhere.
  Per-repo opt-out via `enabledPlugins = false` in
  `.claude/settings.local.json` or project `.claude/settings.json`.
- **Project scope enabled** (`.claude/settings.json` checked in
  with `enabledPlugins["gitmoji@ddaanet"] = true`): plugin loaded
  in this repo for everyone who clones. SessionStart fires; hook
  materialized. Auto-install-on-clone works without any explicit
  per-clone step from teammates.
- **Plugin not enabled in scope**: SessionStart doesn't fire. Any
  hook materialized in a previous session persists in `.git/hooks/`
  until manually removed.

An earlier design used a bespoke plugin-owned flag
(`pluginConfigs["gitmoji@ddaanet"].options.enabled`) for per-repo
opt-in on top of a globally-enabled plugin. That two-lever model
was dropped: it duplicated `enabledPlugins`, ran afoul of Claude
Code's auto-mode classifier hard-blocking agent edits to
`.claude/settings.json`, and produced a footgun where a more-
specific override layer could silently tear down a working hook
on SessionStart.

## Materialization

On every Claude Code session in a repo where the plugin is enabled,
`hooks/hooks.json` fires the SessionStart event, which runs
`scripts/session-materialize.sh`. That script:

1. Resolves the repo root from `${CLAUDE_PROJECT_DIR}`.
2. If not inside a git repo: silent exit 0.
3. If `.git/hooks/commit-msg` exists without the
   `gitmoji-plugin-installed` marker: print a warning, exit 0
   (refuse to clobber an unrelated user hook).
4. Otherwise: copy `gitmoji.sh`, `gitmoji.cfg`, and
   `commit-msg.template` from `${CLAUDE_PLUGIN_ROOT}/scripts/`
   into `.git/hooks/`, `chmod +x` the executables, log a line.

Per-repo hook files are thus a **cache**, regenerated from the
plugin version running in the current session. Plugin upgrades
propagate automatically: the next SessionStart rewrites
`.git/hooks/` from the new version.

The script never tears down. The plugin has no event for "I was
disabled," so cleanup is a user-explicit action (see "The disable
asymmetry" below).

## The disable asymmetry

Plugin install is implicit (SessionStart side-effect of the plugin
being enabled). Plugin disable/uninstall has no counterpart event
in the plugin's namespace — when the plugin stops being loaded, no
plugin code runs to clean up. The hook files in `.git/hooks/`
therefore persist after `/plugin uninstall` or scope-level disable,
and git keeps running them.

This is structural; any SessionStart-driven materialization has
the same property. The plugin ships `/gitmoji:uninstall` as the
user-explicit verb that removes the marker-tagged hook files. It
is the only user-visible slash command the plugin owns. The
asymmetry is intentional: install is automatic so there is no
matching `/gitmoji:install`.

Users are documented to run `/gitmoji:uninstall` in each opted-in
repo **before** disabling or uninstalling the plugin globally. If
they don't, the hook keeps rewriting conventional prefixes — which
is what they had opted in to — and they can clean up by running
`bash $CLAUDE_PLUGIN_ROOT/scripts/uninstall-hook.sh` (while the
plugin cache lingers) or by removing the three hook files manually.

## Requirements this design meets

- **Automatic on plugin update.** SessionStart re-materializes from the
  current plugin version on every session. No manual per-repo action.
- **Transparent.** Users never see the mechanics — they enable the
  plugin in a scope and the hook appears.
- **Safe when project-local plugin versions differ.** Each repo's
  `.git/hooks/` are rewritten only by sessions opened on that repo,
  using whichever plugin version that session sees. Repos do not share
  any state, so mixed versions across repos never conflict.
- **Git-tracked opt-in.** Checking `enabledPlugins["gitmoji@ddaanet"]
  = true` into a repo's `.claude/settings.json` makes the hook
  travel with the repo; fresh clones auto-materialize on first
  session.

## Safety rules

- **Marker-based idempotence.** The wrapper `commit-msg` hook contains a
  `gitmoji-plugin-installed` comment. The materializer refuses to
  overwrite anything without that marker; the uninstaller refuses to
  remove anything without it.
- **Lowercase-only conventional prefixes.** The regex `^([a-z]+):\ (.*)`
  is intentional. Mixed-case or dotted prefixes are rejected with a
  helpful message listing valid prefixes, not silently mangled.
- **Already-emoji detection.** If the first line starts with a known
  emoji, the hook exits 0 without touching the message. Re-running the
  hook on the same message is safe.
- **Merge/squash/amend skipping.** The hook exits 0 for these source
  types, so the plugin never corrupts merge commit messages.

## Dependencies

No runtime dependencies beyond bash and git. `jq` was previously
required at runtime to read and edit `.claude/settings.json`; with
the flag gone, the materializer and uninstall script no longer
parse JSON. `jq` is still used by `just precommit` to validate
manifest JSON, but that is a development concern only.

## Decomposition

- **`commands/uninstall.md`**: the only user-visible slash command.
  Body instructs Claude to shell out to
  `${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh` with
  `dangerouslyDisableSandbox: true`. No `commands/install.md` —
  install is implicit.
- **`hooks/hooks.json`**: registers the SessionStart hook that
  invokes `session-materialize.sh`.
- **`scripts/session-materialize.sh`**: install-or-refresh entry
  point. Runs on every SessionStart when the plugin is enabled in
  the current scope. Never tears down. Idempotent. ~30 lines, no
  jq.
- **`scripts/uninstall-hook.sh`**: removes the marker-tagged hook
  files from the current repo. Backs both `/gitmoji:uninstall`
  and `just uninstall`. Idempotent. Runnable from any shell —
  remains usable after the plugin has been disabled in Claude
  Code, since the plugin cache persists until the user clears it.
- **`scripts/gitmoji.sh`** / **`scripts/gitmoji.cfg`**: the hook
  body and prefix mapping. Source of truth for both.
- **`scripts/commit-msg.template`**: the marker-tagged
  `commit-msg` wrapper. Copied verbatim into
  `.git/hooks/commit-msg` by the materializer and by manual
  setups. Existing as a real file lets the materializer `cp` it
  without retyping shell metacharacters.

## Relationship to upstream devddaanet

The scripts originated in `devddaanet/scripts/`. With this plugin in
place, the source of truth migrates here:

- Bug fixes and new prefixes land in this plugin first.
- `devddaanet` may eventually drop its local copies and depend on the
  plugin, though that's out of scope for this plugin.

## Non-goals

- Custom per-repo mappings. Fork `gitmoji.cfg` or override in a
  per-repo wrapper if needed.
- Non-conventional-commit prefix styles.
- A `pre-commit` variant. `commit-msg` is the correct event for message
  rewriting (pre-commit fires before the message is composed).

## Open questions

- Should `gitmoji.cfg` be editable without forking? A `~/.gitmoji.cfg`
  override could be supported; deferred until there is demand.
- Could the materializer do anything useful when Claude Code is opened
  on a non-git directory? Currently it silently exits. Probably fine.
