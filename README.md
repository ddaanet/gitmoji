# gitmoji

Commit-msg git hook that replaces conventional-commit prefixes with
[gitmoji](https://gitmoji.dev/) emojis. Ships as a Claude Code plugin with
install / uninstall commands.

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

Then install the hook into the current repository:

```
/gitmoji:install
```

To uninstall the hook (the plugin stays installed, only the repo-level
hook is removed):

```
/gitmoji:uninstall
```

### Manual install

Without the plugin command, run the script directly from a clone of this
repo:

```
bash scripts/install-hook.sh
```

Or use the justfile: `just install`.

## Safety

The installer refuses to overwrite an existing `commit-msg` hook unless
it was installed by this plugin (detected via a marker comment in the
hook). Move or remove the existing hook first.

The uninstaller only removes files carrying the marker.

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

Edit `scripts/gitmoji.cfg` to customise.

## License

MIT
