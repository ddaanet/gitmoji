# gitmoji

Commit-msg git hook that replaces conventional-commit prefixes with
[gitmoji](https://gitmoji.dev/) emojis. Ships as a Claude Code plugin
with settings-driven opt-in.

## What it does

On commit, the hook rewrites the first line of the commit message:

```
feat: add new feature    →   ✨ add new feature
fix: handle edge case    →   🐛 handle edge case
docs: update README      →   📝 update README
```

Mapping in [`scripts/gitmoji.cfg`](scripts/gitmoji.cfg). The hook is a
no-op for merge, squash, and amend messages, and leaves alone any
message already starting with a known emoji.

Invalid prefix or missing prefix → commit rejected with a listing of
valid prefixes.

## Installation

Install the plugin from the `ddaanet` marketplace:

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install gitmoji@ddaanet
```

Then opt the current repo in:

```
/gitmoji:install
```

This writes `gitmoji.enabled: true` into `.claude/settings.json`
(checked in — every teammate gets the hook on their next Claude Code
session). The plugin's SessionStart hook re-materializes the
`.git/hooks/commit-msg` wrapper from the current plugin version on
every session, so plugin upgrades propagate with zero per-repo work.

Opt the repo out:

```
/gitmoji:uninstall
```

### Opt-in scopes

`gitmoji.enabled` is resolved from Claude Code's standard settings
hierarchy (more specific wins):

1. `.claude/settings.local.json` (this repo, per-user, gitignored)
2. `.claude/settings.json` (this repo, checked in) — where the slash
   commands write
3. `~/.claude/settings.json` (your user defaults)

To opt in **everywhere**, set `"gitmoji": {"enabled": true}` in
`~/.claude/settings.json`. To opt out in one repo, set it to `false` in
`.claude/settings.local.json`.

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

`jq` on `PATH`. The installer, uninstaller, and SessionStart
materializer use it to read and edit `.claude/settings.json`.

## License

MIT
