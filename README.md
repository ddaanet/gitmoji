# gitmoji

Commit-msg git hook that replaces conventional-commit prefixes with
[gitmoji](https://gitmoji.dev/) emojis. Ships as a Claude Code plugin
with settings-driven opt-in.

## What it does

On commit, the hook rewrites the first line of the commit message:

```
feat: add new feature       →   ✨ add new feature
fix: handle edge case       →   🐛 handle edge case
docs: update README         →   📝 update README
feat(api): add endpoint     →   ✨ api: add endpoint
feat!: drop python 3.8      →   ✨💥 drop python 3.8
refactor(api)!: rename it   →   ♻️💥 api: rename it
```

Mapping in [`scripts/gitmoji.cfg`](scripts/gitmoji.cfg). The hook is a
no-op for merge, squash, and amend messages, and leaves alone any
message already starting with a known emoji.

Invalid prefix or missing prefix → commit rejected with a listing of
valid prefixes.

### Scope

An optional scope in parentheses is rendered into the rewritten
subject as `<scope>: <description>`:

    feat(api): add endpoint    →   ✨ api: add endpoint
    fix(core/utils): bug       →   🐛 core/utils: bug

Scope must be lowercase: `[a-z0-9._/-]+`. Empty scope (`feat(): msg`)
is rejected.

### Breaking changes

Mark a breaking change with `!` after the type (and scope, if any). The
hook appends 💥 to the type emoji:

    feat!: drop python 3.8         →   ✨💥 drop python 3.8
    refactor(api)!: rename method  →   ♻️💥 api: rename method

This follows the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
shorthand. The `BREAKING CHANGE:` footer is **not** detected — use `!`
in the subject line to flag breaking changes. A bare emoji subject like
`💥 msg` is rejected; declare a type (`feat!: …`, `refactor!: …`, etc.)
instead.

## Installation

Install the plugin from the `ddaanet` marketplace:

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install gitmoji@ddaanet
```

That enables the plugin at user scope (`~/.claude/settings.json`
gets `enabledPlugins["gitmoji@ddaanet"] = true`). The plugin's
SessionStart hook then installs `.git/hooks/commit-msg` in every
repo you open in Claude Code, so commit messages get rewritten
everywhere.

### Per-repo opt-in (team-shared)

If you want the hook only in specific repos and want teammates to
inherit it automatically, do **not** enable user-scope (or set it
to `false` in `~/.claude/settings.json`). In each repo where you
want gitmoji active, add to the checked-in `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "gitmoji@ddaanet": true
  }
}
```

Teammates cloning the repo inherit the opt-in. On their first
Claude Code session, the plugin's SessionStart installs the hook.

### Per-repo opt-out

To disable gitmoji in a single repo while keeping it on
elsewhere, add to `.claude/settings.local.json` (per-user,
gitignored):

```json
{
  "enabledPlugins": {
    "gitmoji@ddaanet": false
  }
}
```

### Uninstall

To remove the hook from one repo:

```
/gitmoji:uninstall
```

This removes the marker-tagged hook files from `.git/hooks/`. It
does **not** touch `enabledPlugins` — you control that via
`/plugin uninstall` or hand-edit.

**Important:** Run `/gitmoji:uninstall` in each opted-in repo
*before* running `/plugin uninstall gitmoji@ddaanet`. Once the
plugin is uninstalled it can no longer clean up its own hook
files, and the persistent `.git/hooks/commit-msg` will keep
rewriting your messages. If you've already uninstalled, fall back
to `rm .git/hooks/{commit-msg,gitmoji.sh,gitmoji.cfg}` (skips
the marker check — only do this if you're sure those files came
from gitmoji).

## Safety

`.git/hooks/` files are treated as a cache, not state. The materializer
only touches files carrying a `gitmoji-plugin-installed` marker — an
existing `commit-msg` hook without the marker is left alone and the
materializer prints a notice so you can move it manually.

## Prefix → emoji mapping

| Prefix     | Emoji | Meaning |
|------------|-------|---------|
| `feat`     | ✨    | Introduce new features |
| `fix`      | 🐛    | Fix a bug |
| `docs`     | 📝    | Add or update documentation |
| `style`    | 🎨    | Improve structure / format |
| `refactor` | ♻️    | Refactor code |
| `perf`     | ⚡️    | Improve performance |
| `test`     | ✅    | Add / update / pass tests |
| `build`    | 📦️    | Add or update compiled files or packages |
| `ci`       | 👷    | Add or update CI build system |
| `chore`    | 🔧    | Add or update configuration files |
| `revert`   | ⏪️    | Revert changes |
| `hotfix`   | 🚑️    | Critical hotfix |
| `release`  | 🔖    | Release / version tags |

Edit `scripts/gitmoji.cfg` to customise.

## Dependencies

`bash` and `git`. No `jq` at runtime — the materializer and
uninstall script are pure shell with no JSON parsing.

## License

MIT
