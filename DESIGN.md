# gitmoji — Design

Living document. Captures the research, analysis, and decisions behind
this plugin. Updated as the design evolves.

Last updated: 2026-04-20.

## Problem

The `devddaanet` repo has a commit-msg hook (`scripts/gitmoji.sh` +
`scripts/gitmoji.cfg`) installed via `just install`. It's useful outside
that repo too. Packaging it as a standalone plugin lets any Claude Code
user install it in their own repos without cloning `devddaanet`.

## Analysis — why a plugin and not a gist / standalone script

A plugin gets:

- Distribution via the `ddaanet` marketplace (discoverable, versioned)
- Slash-command UI (`/gitmoji:install`) for a one-shot setup
- Clean coupling between the hook scripts and the installer (same repo,
  `${CLAUDE_PLUGIN_ROOT}` resolves at runtime)
- Uninstall path with an explicit marker

What it does *not* need:

- A Claude Code hook. This plugin ships a *git* hook, not a Claude Code
  hook. The plugin's hooks directory stays empty.
- A skill. The action is a one-shot user-triggered setup; a slash command
  is the simpler fit. "Skill shines when the agent decides when to run;
  command wins for user-triggered setup."

## Decomposition

- **`commands/install.md`**: the user-facing trigger. Content tells the
  agent to run `${CLAUDE_PLUGIN_ROOT}/scripts/install-hook.sh`.
- **`scripts/install-hook.sh`**: deterministic installer. Locates git
  root, copies `gitmoji.sh` + `gitmoji.cfg` to `.git/hooks/`, writes a
  wrapper `commit-msg` hook that execs the copied `gitmoji.sh`.
- **`scripts/gitmoji.sh`**: the hook itself. Lifted verbatim from
  `devddaanet/scripts/gitmoji.sh`. Source of truth now lives here.
- **`scripts/gitmoji.cfg`**: prefix → emoji mapping. Lifted verbatim.
- **`scripts/uninstall-hook.sh`**: mirror of the installer. Only touches
  files carrying the plugin-installed marker.

## Safety rules

- **Marker-based idempotence.** The wrapper `commit-msg` hook contains a
  `gitmoji-plugin-installed` comment. The installer refuses to overwrite
  anything without that marker; the uninstaller refuses to remove
  anything without it. This prevents stomping on unrelated
  user-configured hooks.
- **Lowercase-only conventional prefixes.** The regex `^([a-z]+):\ (.*)`
  is intentional. Mixed-case or dotted prefixes are rejected with a
  helpful message listing valid prefixes, not silently mangled.
- **Already-emoji detection.** If the first line starts with a known
  emoji, the hook exits 0 without touching the message. Re-running the
  hook on the same message is safe.
- **Merge/squash/amend skipping.** The hook exits 0 for these source
  types, so the plugin never corrupts merge commit messages.

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

- Should the plugin additionally expose the hook via a Claude Code hook
  for automatic install on session start? Probably not — that would
  silently modify every repo the user opens in Claude Code. Keeping it
  explicit (user runs `/gitmoji:install`) preserves consent.
- Should `gitmoji.cfg` be editable without forking? A `~/.gitmoji.cfg`
  override could be supported; deferred until there is demand.
