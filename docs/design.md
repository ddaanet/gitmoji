# gitmoji — Design

Living design document. Updated when meaningful design decisions land
or get overturned. Not a changelog of features — a record of *why this
plugin has the shape it has*.

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

Why there is no plugin-owned opt-in flag (for example a
`pluginConfigs["gitmoji@ddaanet"].options.enabled` layered on top of
a globally enabled plugin):

- It duplicates `enabledPlugins`, giving two levers for one decision.
- Agents cannot set it: Claude Code's auto-mode classifier
  hard-blocks agent edits to `.claude/settings.json`, whereas
  `enabledPlugins` is toggled by the user through `/plugin`.
- A more specific override layer could silently flip it and make
  SessionStart tear down a working hook.

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
  hook materialized in a previous session persists in the hooks dir
  until manually removed.

## Materialization

On every Claude Code session in a repo where the plugin is enabled,
`hooks/hooks.json` fires the SessionStart event, which runs
`scripts/session-materialize.sh`. That script:

1. Locates the repo from `${CLAUDE_PROJECT_DIR}`.
2. If not inside a git repo: silent exit 0.
3. If `core.hooksPath` is set: install and write nothing, emit a
   status line and agent context saying so, exit 0 (see "Where the
   hook is installed").
4. If `<hooks dir>/commit-msg` exists without the
   `gitmoji-plugin-installed` marker: leave it in place, emit a
   status line and agent context, exit 0 (refuse to clobber an
   unrelated user hook).
5. Otherwise: copy `gitmoji.sh`, `gitmoji.cfg`, and
   `commit-msg.template` from `${CLAUDE_PLUGIN_ROOT}/scripts/`
   into `<hooks dir>/`, `chmod +x` the executables, and emit a
   status line (installed / refreshed / already current) plus
   agent context.

The agent context (`additionalContext`) states the commit-message
form to write: a plain conventional prefix, no emoji, with the hook
adding the emoji. It does not describe the rewrite, because an agent
imitates the emoji-prefixed `git log` it already sees. The text is
the same in every installing state and carries no uninstall pointer.
For a foreign hook it only directs the agent to read that hook: no
offer to remove it and no marker name.

### Where the hook is installed

`<hooks dir>` is `$(git rev-parse --git-common-dir)/hooks`, made
absolute, git's default hooks directory. It is not
`<toplevel>/.git/hooks`: in a linked worktree and in a submodule
`.git` is a file, so that path does not exist. The common dir is
shared by every worktree of a repo, so one installation covers them
all and the hook files have a single owner. A session in any
worktree where the plugin is enabled therefore installs the hook for
every worktree of the repo, including ones whose settings do not
enable it. A submodule has its own
git dir under the superproject's `.git/modules/<name>`, so it gets
its own hook files there and the superproject's are untouched.

A repo with `core.hooksPath` set (husky, lefthook) is treated as
running its own hooks. Git no longer reads the default hooks dir
there, so a hook installed in it would never fire while the agent
was told it adds the emoji. The path the setting names is usually a
checked-in directory owned by another tool, which is not the
plugin's to write to. The plugin therefore installs nothing, and
the agent context says that nothing adds emoji, so the agent
follows the repo's own commit-message convention.

The uninstaller resolves the same common hooks dir and ignores
`core.hooksPath`. That dir is the only place the plugin ever
installs, so a hook left there from before the setting appeared is
still removable.

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
- **Lowercase-only conventional prefixes.** The hook accepts the full
  Conventional Commits 1.0.0 first-line grammar
  `type[(scope)][!]: description`, with type matching `[a-z]+` and
  scope matching `[a-z0-9._/-]+`. Mixed-case or dotted types,
  uppercase scopes, and bare-emoji subjects (`💥 msg`) are rejected
  with a message listing valid prefixes, not silently mangled. Empty
  scope (`feat(): msg`) gets a distinct diagnosis that quotes the
  offending prefix.
- **Every rejection ends with the form to write.** Each rejection
  prints one diagnosis line, the valid prefixes, and a final line
  stating the act: write the first line as
  `type[(scope)][!]: description`, with no emoji, because the hook adds
  the emoji. The line is identical for every rejection and comes last
  so that output truncated with `| tail` keeps it. The hook does not
  try to recognise emoji-led subjects, since the act line serves every
  malformed subject alike.
- **Scope rendering.** A parenthesised scope is preserved by
  prepending it to the description as `<scope>: …` in the rewritten
  subject, so reviewers don't lose it.
- **Breaking-change rendering.** The Conventional Commits `!` marker
  appends `💥` to the type emoji with no intervening space, so
  `✨💥 …` reads as a single visual token. `💥` is a script-local
  constant, not a parseable type. The `BREAKING CHANGE:` footer is
  not inspected; see Non-goals.
- **Already-emoji detection.** If the first line starts with a known
  emoji, the hook exits 0 without touching the message. Re-running the
  hook on the same message is safe.
- **Git-authored message skipping.** When git composes the message
  itself, the hook exits 0 and leaves it byte-for-byte alone. Rejecting
  such a message strands the operation — a rejected merge reports
  `Not committing merge; use 'git commit' to complete the merge` and
  leaves it staged but uncommitted. Two signals, because neither covers
  everything:
  - A state marker in `$(git rev-parse --git-dir)`: `MERGE_HEAD`,
    `SQUASH_MSG`, `CHERRY_PICK_HEAD`, or `REVERT_HEAD`. Each is
    cleared by the commit or the `--abort` that ends its operation, so
    a marker can never outlive its operation and silently disable the
    hook for later commits.
  - A `fixup! ` / `squash! ` / `amend! ` first line. Autosquash
    subjects carry no marker, so the message is the only signal.

  Nothing else suffices. Git passes `commit-msg` **exactly one
  argument**, so there is no source-type to consult — the `$2`-based
  `case` this replaced was written to `prepare-commit-msg` semantics
  and never once matched in production. The message file is
  `COMMIT_EDITMSG`, not `MERGE_MSG`, whenever a conflicted or
  interrupted merge is completed by hand, so the file's basename is
  not a sufficient test either. `GIT_DIR` is not exported into the
  hook environment, hence `git rev-parse`.

  Clean `revert`, clean `cherry-pick`, and `rebase --continue` need no
  handling: they never invoke the `commit-msg` hook at all. Only their
  conflict continuations do, which is where the markers apply.
  `--amend` and rebase `reword` do invoke it, but are handed the
  commit's existing message, which already carries an emoji and exits
  via the round-trip check above.

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
  the current scope. Never tears down. Idempotent. No jq.
- **`scripts/uninstall-hook.sh`**: removes the marker-tagged hook
  files from the current repo's common hooks dir. Backs both `/gitmoji:uninstall`
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
- `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer detection. The hook
  reads only the first line. Footer support is purely additive and
  could be added later without changing the first-line grammar.

## Open questions

- Should `gitmoji.cfg` be editable without forking? A `~/.gitmoji.cfg`
  override could be supported; deferred until there is demand.
- Could the materializer do anything useful when Claude Code is opened
  on a non-git directory? Currently it silently exits. Probably fine.
