# gitmoji — Design

Living document. Captures the research, analysis, and decisions behind
this plugin. Updated as the design evolves.

Last updated: 2026-05-08.

## Problem

The `devddaanet` repo has a commit-msg hook (`scripts/gitmoji.sh` +
`scripts/gitmoji.cfg`) installed via `just install`. It's useful outside
that repo too. Packaging it as a standalone plugin lets any Claude Code
user install it in their own repos without cloning `devddaanet`.

## Analysis — why a plugin and not a gist / standalone script

A plugin gets:

- Distribution via the `ddaanet` marketplace (discoverable, versioned)
- Slash-command UI (`/gitmoji:install`) for a one-shot setup
- A SessionStart hook we can use to keep per-repo state in sync with the
  plugin version
- Clean coupling between the hook scripts and the installer (same repo,
  `${CLAUDE_PLUGIN_ROOT}` resolves at runtime)
- Uninstall path with an explicit marker

What it does *not* need:

- A skill. The action is user-triggered setup; a slash command is the
  simpler fit.

## Opt-in model

**Opt-in lives in `.claude/settings.json`, not in `.git/hooks/`.** Hook
files are not git-tracked, so a cloned repo that "wants gitmoji" cannot
signal that through `.git/hooks/`. A checked-in `.claude/settings.json`
with `gitmoji.enabled: true` is the correct source of truth — it
travels with the repo.

The effective value of `gitmoji.enabled` is read across the standard
Claude Code hierarchy (more specific wins):

1. `.claude/settings.local.json` (repo, per-user, gitignored)
2. `.claude/settings.json` (repo, checked in)
3. `~/.claude/settings.json` (user)

Managed (enterprise) and CLI overrides sit above these, inherited from
Claude Code's normal precedence rules.

## Materialization

On every Claude Code session, `hooks/hooks.json` fires the SessionStart
event, which runs `scripts/session-materialize.sh`. That script:

1. Resolves the repo root from `${CLAUDE_PROJECT_DIR}`.
2. Reads `gitmoji.enabled` from the hierarchy above.
3. If `true`: copies `gitmoji.sh` + `gitmoji.cfg` into `.git/hooks/`
   and writes a marker-tagged `commit-msg` wrapper.
4. If `false` or unset: removes any marker-tagged hook files.
5. Refuses to stomp a `commit-msg` that lacks the marker.

Per-repo hook files are thus a **cache**, regenerated from the plugin
version running in the current session. Plugin upgrades propagate
automatically: the next SessionStart rewrites `.git/hooks/` from the
new version.

The slash commands `/gitmoji:install` and `/gitmoji:uninstall` toggle
`gitmoji.enabled` in project-scope `.claude/settings.json` and
materialize (or tear down) the per-repo hook files immediately, so the
user doesn't have to wait for the next session to see the effect.
They drive the harness `Read`/`Edit`/`Write` tools directly rather
than shelling out to the bash scripts (see "Why slash commands do not
invoke the bash scripts" below).

### Why slash commands do not invoke the bash scripts

Claude Code's sandbox blocks Bash from writing to `.claude/settings.json`
and `.git/hooks/`. Running `bash install-hook.sh` from inside a Claude
Code session therefore requires the user to approve a broad sandbox-
bypass prompt. The `Edit`/`Write` tools run in the harness, above the
Bash sandbox, and can mutate those paths without any sandbox escape.
Whether they surface a normal tool-permission prompt depends on the
user's permission mode (in `auto` mode they have been observed to
proceed without prompts; stricter modes may prompt per file).

`scripts/install-hook.sh` and `scripts/uninstall-hook.sh` remain in
the repo for users running directly from a shell (e.g. `bash
scripts/install-hook.sh` outside Claude Code), and as the bodies of
SessionStart materialization. They are no longer the slash command
implementation.

## Requirements this design meets

- **Automatic on plugin update.** SessionStart re-materializes from the
  current plugin version on every session. No manual per-repo action.
- **Transparent.** Users never see the mechanics — they set a settings
  entry (via slash command or manually) and the hook appears.
- **Safe when project-local plugin versions differ.** Each repo's
  `.git/hooks/` are rewritten only by sessions opened on that repo,
  using whichever plugin version that session sees. Repos do not share
  any state, so mixed versions across repos never conflict.
- **Git-tracked opt-in.** `.claude/settings.json` travels with the
  repo, so fresh clones auto-materialize on first session.

## Safety rules

- **Marker-based idempotence.** The wrapper `commit-msg` hook contains a
  `gitmoji-plugin-installed` comment. The materializer refuses to
  overwrite anything without that marker; teardown refuses to remove
  anything without it.
- **Lowercase-only conventional prefixes.** The regex `^([a-z]+):\ (.*)`
  is intentional. Mixed-case or dotted prefixes are rejected with a
  helpful message listing valid prefixes, not silently mangled.
- **Already-emoji detection.** If the first line starts with a known
  emoji, the hook exits 0 without touching the message. Re-running the
  hook on the same message is safe.
- **Merge/squash/amend skipping.** The hook exits 0 for these source
  types, so the plugin never corrupts merge commit messages.

## Dependencies

- `jq` is required. The installer, uninstaller, and materializer use it
  to read and edit settings JSON. Scripts fail with a clear message if
  `jq` is missing.

## Decomposition

- **`commands/install.md`** / **`commands/uninstall.md`**: user-facing
  slash commands. Their bodies instruct Claude to edit
  `.claude/settings.json` and materialize/tear down the `.git/hooks/`
  files using the harness `Read`/`Edit`/`Write` tools (plus a single
  `chmod` on install). They do not invoke the bash installer scripts.
- **`hooks/hooks.json`**: registers the SessionStart hook that invokes
  `session-materialize.sh`.
- **`scripts/session-materialize.sh`**: single entry point for
  writing/removing per-repo hook files based on the effective
  `gitmoji.enabled` setting. Idempotent.
- **`scripts/install-hook.sh`** / **`scripts/uninstall-hook.sh`**:
  shell entry points for users running outside Claude Code. Toggle
  `gitmoji.enabled` in project-scope `.claude/settings.json` and
  invoke the materializer. The slash commands no longer call these
  scripts; they exist for direct-shell use only.
- **`scripts/gitmoji.sh`** / **`scripts/gitmoji.cfg`**: the hook body
  and prefix mapping. Source of truth for both lives here.
- **`scripts/commit-msg.template`**: the marker-tagged `commit-msg`
  wrapper. Copied verbatim into `.git/hooks/commit-msg` by both
  `session-materialize.sh` and the `/gitmoji:install` slash command.
  Existing as a real file (rather than an inline heredoc) lets the
  install command `Read`/`Write` it without having to retype shell
  metacharacters.

## Relationship to upstream devddaanet

The scripts originated in `devddaanet/scripts/`. With this plugin in
place, the source of truth migrates here:

- Bug fixes and new prefixes land in this plugin first.
- `devddaanet` may eventually drop its local copies and depend on the
  plugin (install via `/gitmoji:install`), though that's out of scope
  for this plugin.

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
