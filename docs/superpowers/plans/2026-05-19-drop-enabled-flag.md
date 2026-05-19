# Drop pluginConfigs.options.enabled — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bespoke `pluginConfigs["gitmoji@ddaanet"].options.enabled` opt-in flag with Claude Code's native `enabledPlugins` mechanism. Collapse the plugin surface to a SessionStart hook + materializer + a single `/gitmoji:uninstall` cleanup command.

**Architecture:** SessionStart fires only when the plugin is enabled in the resolved scope chain; if it fires, install/refresh the hook files in `.git/hooks/` unconditionally. No more settings parsing, no more teardown branch, no more `/gitmoji:install`. Uninstall is the only user-explicit slash command — it removes the marker-tagged hook files and is documented as "run before disabling the plugin."

**Tech Stack:** Bash, jq (dev-only; removed from runtime path), `just` recipes, `claude -p` for integration tests.

**Spec:** `docs/superpowers/specs/2026-05-19-drop-enabled-flag-design.md`

---

## File structure (decomposition)

**Delete:**
- `commands/install.md`
- `scripts/install-hook.sh`
- `tests/install.sh`

**Modify:**
- `scripts/session-materialize.sh` — strip jq/settings/teardown; install-or-refresh only
- `scripts/uninstall-hook.sh` — strip jq/settings mutation; just rm hook files with marker check
- `commands/uninstall.md` — shell to `scripts/uninstall-hook.sh` with `dangerouslyDisableSandbox: true`
- `tests/uninstall.sh` — drop settings.json assertions; assert hook removal only; allow `bash`
- `hooks/hooks.json` — update description string
- `.claude-plugin/plugin.json` — refresh description (version bump handled by `just release`)
- `justfile` — drop `install` and `test-install` recipes; add `test-materialize`
- `.gitignore` — drop `.test-install-*`
- `CLAUDE.md` — rewrite Layout, Opt-in model, Conventions, Testing
- `DESIGN.md` — rewrite Opt-in/Materialization/Decomposition, delete Why-slash-commands-do-not-invoke-bash, add asymmetry section, rewrite Dependencies
- `README.md` — new install flow, document asymmetry, update dependencies

**Add:**
- `tests/materialize.sh` — direct-invocation integration test for the new materializer

**Unchanged:**
- `scripts/gitmoji.sh`, `scripts/gitmoji.cfg`, `scripts/commit-msg.template`

---

## Task 1: Add failing test for new materializer behavior

**Files:**
- Create: `tests/materialize.sh`
- Modify: `justfile` (add `test-materialize` recipe)

- [ ] **Step 1: Write the test**

Create `tests/materialize.sh` with the four scenarios documented in the design (fresh repo, repo with marker hook, repo with foreign hook, non-git dir):

```bash
#!/usr/bin/env bash
# Integration test: scripts/session-materialize.sh installs the
# commit-msg hook unconditionally when run inside a git repo, with
# NO settings.json flag present. Refuses to clobber a non-marker
# commit-msg. Silent no-op outside a git repo.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"

scratch_root="$(mktemp -d "$plugin_root/.test-materialize-XXXXXX")"
trap 'rm -rf "$scratch_root"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# --- Scenario 1: fresh git repo, no settings.json flag.
# The new materializer must install regardless of settings.
case1="$scratch_root/case1"
mkdir -p "$case1"
git -C "$case1" init -q

CLAUDE_PROJECT_DIR="$case1" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case1: materializer exited non-zero on fresh repo"

[ -f "$case1/.git/hooks/commit-msg" ]   || fail "case1: commit-msg not installed"
[ -x "$case1/.git/hooks/commit-msg" ]   || fail "case1: commit-msg not executable"
grep -q "gitmoji-plugin-installed" "$case1/.git/hooks/commit-msg" \
    || fail "case1: commit-msg missing marker"
[ -f "$case1/.git/hooks/gitmoji.sh" ]   || fail "case1: gitmoji.sh not installed"
[ -x "$case1/.git/hooks/gitmoji.sh" ]   || fail "case1: gitmoji.sh not executable"
[ -f "$case1/.git/hooks/gitmoji.cfg" ]  || fail "case1: gitmoji.cfg not installed"

# Confirm no settings.json was touched.
[ ! -f "$case1/.claude/settings.json" ] || fail "case1: materializer wrote settings.json"

# --- Scenario 2: existing marker-tagged commit-msg (upgrade path).
# Materializer should refresh files in place.
case2="$scratch_root/case2"
mkdir -p "$case2/.git/hooks"
git -C "$case2" init -q
cat > "$case2/.git/hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
# gitmoji-plugin-installed
# stale-content
EOF
chmod +x "$case2/.git/hooks/commit-msg"

CLAUDE_PROJECT_DIR="$case2" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case2: materializer exited non-zero on marker-tagged hook"

# After refresh, content should match the template verbatim.
diff "$case2/.git/hooks/commit-msg" "$plugin_root/scripts/commit-msg.template" \
    || fail "case2: commit-msg not refreshed to template content"
diff "$case2/.git/hooks/gitmoji.sh" "$plugin_root/scripts/gitmoji.sh" \
    || fail "case2: gitmoji.sh not refreshed"
diff "$case2/.git/hooks/gitmoji.cfg" "$plugin_root/scripts/gitmoji.cfg" \
    || fail "case2: gitmoji.cfg not refreshed"

# --- Scenario 3: foreign (non-marker) commit-msg present.
# Materializer must refuse to overwrite, warn, exit 0.
case3="$scratch_root/case3"
mkdir -p "$case3/.git/hooks"
git -C "$case3" init -q
cat > "$case3/.git/hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
# someone else's hook
echo "foreign hook"
EOF
chmod +x "$case3/.git/hooks/commit-msg"
foreign_sha=$(sha256sum "$case3/.git/hooks/commit-msg" | cut -d' ' -f1)

CLAUDE_PROJECT_DIR="$case3" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case3: materializer exited non-zero on foreign hook"

new_sha=$(sha256sum "$case3/.git/hooks/commit-msg" | cut -d' ' -f1)
[ "$foreign_sha" = "$new_sha" ] || fail "case3: materializer overwrote a foreign commit-msg"

# --- Scenario 4: outside a git repo. Silent exit 0.
case4="$scratch_root/case4"
mkdir -p "$case4"
CLAUDE_PROJECT_DIR="$case4" bash "$plugin_root/scripts/session-materialize.sh" \
    || fail "case4: materializer exited non-zero outside git repo"
[ ! -d "$case4/.git" ] || fail "case4: materializer created a .git directory"

echo "PASS"
```

- [ ] **Step 2: Wire it into justfile**

Edit `justfile`:

Replace the test-integration block (lines 40–51) so that:
- `test-install` is removed (the slash command is going away).
- `test-materialize` is added.
- `test-integration` runs `test-materialize` and `test-uninstall`.

```just
# Integration test: SessionStart materializer installs the per-repo
# hook unconditionally when invoked, with marker-protection on
# non-gitmoji commit-msg hooks.
test-materialize:
    bash tests/materialize.sh

# Integration test: drive /gitmoji:uninstall via `claude -p` and assert
# the slash command removes the hook files without touching
# `.claude/settings.json`.
test-uninstall:
    bash tests/uninstall.sh

# Run all integration tests.
test-integration: test-materialize test-uninstall
```

Also remove the `install` recipe (lines 21–23):

```just
# Install the hook in the current git repo
install:
    bash scripts/install-hook.sh
```

…will be deleted entirely in Task 7. For this task, leave it in place to keep diffs focused.

- [ ] **Step 3: Run the test against current code; verify it fails**

```bash
chmod +x tests/materialize.sh
bash tests/materialize.sh
```

Expected: FAIL in case1 with "case1: commit-msg not installed". The current materializer reads `pluginConfigs["gitmoji@ddaanet"].options.enabled` and finds nothing, so it skips installation. This is the correct pre-implementation failure.

- [ ] **Step 4: Update `.gitignore`**

Add `.test-materialize-*` to `.gitignore`. Keep `.test-install-*` for now (will be removed in Task 7 alongside the install artifacts).

```
# Integration test scratch directories (mktemp -d under cwd)
.test-install-*
.test-uninstall-*
.test-materialize-*
```

- [ ] **Step 5: Commit**

```bash
git add tests/materialize.sh justfile .gitignore
git commit -m "test: add failing materialize test for unconditional install"
```

---

## Task 2: Rewrite session-materialize.sh to install unconditionally

**Files:**
- Modify: `scripts/session-materialize.sh`

- [ ] **Step 1: Replace the script body**

Open `scripts/session-materialize.sh` and replace the entire contents (lines 1–63) with:

```bash
#!/usr/bin/env bash
# Materialize (install or refresh) the per-repo commit-msg hook from
# this invocation's plugin version. Runs on every SessionStart in
# repos where the plugin is enabled (resolved via Claude Code's
# enabledPlugins). When this script runs, the plugin is enabled here,
# so install unconditionally; never tear down. Refuses to overwrite a
# foreign commit-msg without the `gitmoji-plugin-installed` marker.
# Idempotent.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    exit 0
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

mkdir -p "$hooks_dir"
if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "gitmoji: existing commit-msg hook at $target; leaving alone (move it to enable)" >&2
    exit 0
fi
cp "$script_dir/gitmoji.sh"  "$hooks_dir/gitmoji.sh"
cp "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"
chmod +x "$hooks_dir/gitmoji.sh"
cp "$script_dir/commit-msg.template" "$target"
chmod +x "$target"
echo "gitmoji: materialized commit-msg hook at $target"
```

Key changes:
- jq dependency check removed.
- Settings precedence loop (`read_setting` + the `for f in ...` block) removed.
- `if [[ "$enabled" == "true" ]]; then ... else ...` collapsed: no `else` branch.

- [ ] **Step 2: Shellcheck**

```bash
shellcheck -x scripts/session-materialize.sh
```

Expected: no output (clean pass).

- [ ] **Step 3: Run the materialize test**

```bash
bash tests/materialize.sh
```

Expected: `PASS`.

- [ ] **Step 4: Smoke-test in-place**

```bash
just materialize
```

Expected output (this repo already has the hook installed): `gitmoji: materialized commit-msg hook at /Users/david/code/gitmoji/.git/hooks/commit-msg`. The hook in `.git/hooks/commit-msg` should still pass `just test`.

```bash
just test
```

Expected: `input:  feat: add a thing` → `output: ✨ add a thing`.

- [ ] **Step 5: Commit**

```bash
git add scripts/session-materialize.sh
git commit -m "refactor: drop settings parsing from materializer"
```

---

## Task 3: Rewrite tests/uninstall.sh for new behavior

**Files:**
- Modify: `tests/uninstall.sh`

- [ ] **Step 1: Replace the test body**

Open `tests/uninstall.sh` and replace the contents (lines 1–57) with:

```bash
#!/usr/bin/env bash
# Integration test: /gitmoji:uninstall must remove the marker-tagged
# hook files from .git/hooks/ without modifying .claude/settings.json.
# The slash command shells to scripts/uninstall-hook.sh with
# dangerouslyDisableSandbox: true (auto-approved by the auto-mode
# classifier for plugin scripts writing .git/hooks/).
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "$plugin_root/.test-uninstall-XXXXXX")"
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q
git config user.email test@example.com
git config user.name "Integration Test"

# Set up an installed state directly. No settings.json — the new
# design does not use any plugin-owned settings key.
cp "$plugin_root/scripts/gitmoji.sh"           .git/hooks/gitmoji.sh
cp "$plugin_root/scripts/gitmoji.cfg"          .git/hooks/gitmoji.cfg
cp "$plugin_root/scripts/commit-msg.template"  .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg .git/hooks/gitmoji.sh

output=$(claude \
    --permission-mode bypassPermissions \
    --plugin-dir "$plugin_root" \
    --add-dir "$work" \
    --add-dir "$plugin_root" \
    -p "/gitmoji:uninstall" 2>&1) || status=$?
status=${status:-0}

fail() {
    echo "FAIL: $1" >&2
    echo "--- claude output ---" >&2
    echo "$output" >&2
    echo "--- end claude output ---" >&2
    exit 1
}

[ "$status" -eq 0 ] || fail "claude exited with status $status"

[ ! -f .git/hooks/commit-msg ]  || fail ".git/hooks/commit-msg was not removed"
[ ! -f .git/hooks/gitmoji.sh ]  || fail ".git/hooks/gitmoji.sh was not removed"
[ ! -f .git/hooks/gitmoji.cfg ] || fail ".git/hooks/gitmoji.cfg was not removed"

# Slash command must not have created or modified .claude/settings.json.
[ ! -f .claude/settings.json ] || fail ".claude/settings.json was written by the slash command"

echo "PASS"
```

Key changes from the old test:
- `--disallowedTools "Bash(bash *)"` is gone. The new slash command shells out — denying bash would block it.
- Setup no longer writes `.claude/settings.json` with the old flag (no such flag any more).
- Assertion that `enabledPlugins…enabled == false` is gone. New positive assertion: settings.json was not created.

- [ ] **Step 2: Run the test against current code; verify it fails**

```bash
bash tests/uninstall.sh
```

Expected: FAIL with ".claude/settings.json was written by the slash command". The current `commands/uninstall.md` still writes settings.json, so the assertion catches the unwanted mutation.

- [ ] **Step 3: Commit**

```bash
git add tests/uninstall.sh
git commit -m "test: assert uninstall slash command does not touch settings.json"
```

---

## Task 4: Rewrite scripts/uninstall-hook.sh

**Files:**
- Modify: `scripts/uninstall-hook.sh`

- [ ] **Step 1: Replace the script body**

Open `scripts/uninstall-hook.sh` and replace the contents (lines 1–37) with:

```bash
#!/usr/bin/env bash
# Remove the per-repo gitmoji commit-msg hook from the current git
# repo. Refuses to touch a commit-msg hook that lacks the
# `gitmoji-plugin-installed` marker. Idempotent. No settings.json
# mutation — opt-in is owned by Claude Code's enabledPlugins, not by
# the plugin.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

if [[ -f "$target" ]] && grep -q "$marker" "$target" 2>/dev/null; then
    rm -f "$target" "$hooks_dir/gitmoji.sh" "$hooks_dir/gitmoji.cfg"
    echo "gitmoji: removed commit-msg hook at $target"
elif [[ -f "$target" ]]; then
    echo "gitmoji: existing commit-msg hook at $target lacks the plugin marker; leaving alone" >&2
    exit 0
else
    echo "gitmoji: no commit-msg hook at $target; nothing to do"
fi
```

Key changes from the old script:
- jq dependency check removed.
- Settings.json mutation block removed.
- Call to `session-materialize.sh` removed.
- New explicit branch for "hook exists but no marker" — informative message.

- [ ] **Step 2: Shellcheck**

```bash
shellcheck -x scripts/uninstall-hook.sh
```

Expected: clean pass.

- [ ] **Step 3: Verify justfile `uninstall` recipe still works**

```bash
just uninstall
```

(This will actually remove the hook from the current repo — that's the test. The next session's SessionStart re-materializes it, so it's safe.)

Expected: `gitmoji: removed commit-msg hook at /Users/david/code/gitmoji/.git/hooks/commit-msg`.

Re-materialize to put the hook back so the next commit works:

```bash
just materialize
```

- [ ] **Step 4: Commit**

```bash
git add scripts/uninstall-hook.sh
git commit -m "refactor: drop settings mutation from uninstall script"
```

---

## Task 5: Rewrite commands/uninstall.md to shell out

**Files:**
- Modify: `commands/uninstall.md`

- [ ] **Step 1: Replace the file body**

Open `commands/uninstall.md` and replace the contents (lines 1–63) with:

```markdown
---
description: Uninstall the gitmoji commit-msg hook from the current git repository.
---

Uninstall the gitmoji `commit-msg` hook from the current repository.
Run this **before** disabling or uninstalling the gitmoji plugin — once
the plugin stops loading, there is no SessionStart event to clean up
after itself, and the hook files would persist in `.git/hooks/`.

## Steps

1. Operate on the current working directory. Confirm it is inside a
   git repository; if not, tell the user and stop.

2. Run the cleanup script with the Bash tool, passing
   `dangerouslyDisableSandbox: true`. The script writes to
   `.git/hooks/` which is outside the default sandbox; the auto-mode
   classifier auto-approves the bypass for plugin scripts writing to
   that directory.

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh
   ```

3. Report the result to the user:
   - If the script printed `gitmoji: removed commit-msg hook at …`,
     tell the user the hook is gone and that commit messages in this
     repo will no longer be rewritten.
   - If it printed `gitmoji: existing commit-msg hook at … lacks the
     plugin marker`, tell the user a non-gitmoji `commit-msg` is
     present and was left untouched; they can move it manually if
     desired.
   - If it printed `gitmoji: no commit-msg hook at …`, tell the user
     there was nothing to remove.

## Why this shape

The opt-in mechanism for the plugin is Claude Code's
`enabledPlugins["gitmoji@ddaanet"]` (managed via `/plugin install`,
`/plugin uninstall`, the `/plugins` TUI, or hand-edit of
`.claude/settings.json`). The plugin never writes that key. This
slash command is the only verb the plugin owns — it removes the
materialized hook files so commit-message rewriting stops.

There is no matching `/gitmoji:install`. Installation is automatic:
when the plugin is enabled in a repo's scope chain, SessionStart
fires there and the materializer installs/refreshes the hook files.
```

- [ ] **Step 2: Run the integration test**

```bash
bash tests/uninstall.sh
```

Expected: `PASS`.

- [ ] **Step 3: Run the full integration suite**

```bash
just test-integration
```

Expected: `PASS` for both `test-materialize` and `test-uninstall`.

- [ ] **Step 4: Commit**

```bash
git add commands/uninstall.md
git commit -m "refactor: route /gitmoji:uninstall through the cleanup script"
```

---

## Task 6: Update hooks/hooks.json description

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Edit the description**

Open `hooks/hooks.json` and replace line 2's description:

Old:
```json
"description": "On SessionStart, materialize (or tear down) the per-repo gitmoji commit-msg hook from the current plugin version, driven by the effective gitmoji.enabled setting.",
```

New:
```json
"description": "On SessionStart, materialize (install or refresh) the per-repo gitmoji commit-msg hook from the current plugin version. Fires whenever the plugin is enabled in the resolved scope chain.",
```

- [ ] **Step 2: Validate JSON**

```bash
jq . hooks/hooks.json > /dev/null
```

Expected: no output, no error.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "docs: update SessionStart hook description"
```

---

## Task 7: Delete install artifacts

**Files:**
- Delete: `commands/install.md`, `scripts/install-hook.sh`, `tests/install.sh`
- Modify: `justfile`, `.gitignore`

- [ ] **Step 1: Delete files**

```bash
git rm commands/install.md scripts/install-hook.sh tests/install.sh
```

- [ ] **Step 2: Remove `install` and `test-install` from justfile**

Open `justfile` and delete these recipes:

```just
# Install the hook in the current git repo
install:
    bash scripts/install-hook.sh
```

(Already removed implicitly if the test-integration update in Task 1 also dropped `test-install` from the dependency list — confirm both are gone.)

After this task, the relevant `justfile` block reads:

```just
# Test the hook against a sample commit message
test msg="feat: add a thing":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    trap 'rm -f "$tmp" "$tmp.tmp"' EXIT
    echo "{{msg}}" > "$tmp"
    echo "input:  {{msg}}"
    bash scripts/gitmoji.sh "$tmp" || { echo "hook failed"; exit 1; }
    echo "output: $(cat "$tmp")"

# Integration test: SessionStart materializer installs the per-repo
# hook unconditionally when invoked, with marker-protection on
# non-gitmoji commit-msg hooks.
test-materialize:
    bash tests/materialize.sh

# Integration test: drive /gitmoji:uninstall via `claude -p` and assert
# the slash command removes the hook files without touching
# `.claude/settings.json`.
test-uninstall:
    bash tests/uninstall.sh

# Run all integration tests.
test-integration: test-materialize test-uninstall
```

- [ ] **Step 3: Remove `.test-install-*` from .gitignore**

Open `.gitignore` and delete the line `.test-install-*`. The result should keep `.test-uninstall-*` and `.test-materialize-*`.

- [ ] **Step 4: Verify nothing references the deleted files**

```bash
grep -rn "install-hook\|/gitmoji:install\|tests/install.sh\|commands/install.md" . \
    --exclude-dir=.git \
    --exclude-dir=plugin-dev \
    --exclude-dir=docs \
    || echo "no live references"
```

Expected: `no live references`. (Matches under `docs/` are the spec/plan/CHANGELOG and are intentional historical references; matches under `plugin-dev/` are the vendored toolkit and are not our code.)

- [ ] **Step 5: Run precommit + integration**

```bash
just precommit
just test-integration
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "feat: drop /gitmoji:install — opt-in is now enabledPlugins"
```

---

## Task 8: Update plugin manifest description

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Edit the description**

Open `.claude-plugin/plugin.json` and update line 4:

Old:
```json
"description": "Commit-msg git hook that replaces conventional-commit prefixes (feat:, fix:, docs:, ...) with gitmoji emojis. Ships an installer command that stows the hook into the current git repo.",
```

New:
```json
"description": "Commit-msg git hook that replaces conventional-commit prefixes (feat:, fix:, docs:, ...) with gitmoji emojis. Installs the per-repo hook automatically on SessionStart whenever the plugin is enabled in the current repo.",
```

Do **not** change the `version` field. `just release` bumps it from the last released version when releasing.

- [ ] **Step 2: Validate JSON**

```bash
jq . .claude-plugin/plugin.json > /dev/null
```

Expected: no output, no error.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "docs: update plugin description to reflect SessionStart install"
```

---

## Task 9: Rewrite CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the file body**

Open `CLAUDE.md` and replace the entire contents (lines 1–83) with:

```markdown
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
- The hook must remain a no-op for merge, squash, and amend commits
  (`source_type` of `merge`, `squash`, `commit`).
- Prefix extraction regex: `^([a-z]+):\ (.*)`. Lowercase-only by design.
- `jq` is **not** a runtime dependency. It is used only by
  `just precommit` to validate manifest JSON.

## Testing

- `just test` — runs the hook against a sample commit message.
- `just test msg="docs: update readme"` — custom message.
- `just materialize` — runs the SessionStart materializer against
  the current repo (dev loop for `session-materialize.sh`).
- `just uninstall` — runs the cleanup script against the current
  repo (dev loop for `uninstall-hook.sh`).
- `just test-materialize` / `just test-uninstall` /
  `just test-integration` — integration tests covering both code
  paths end-to-end.

## Non-goals

- Custom mappings per repo. The mapping is a single file; fork or
  patch `gitmoji.cfg` if needed.
- Non-conventional prefix styles (uppercase, dot-separated, etc.).
  Conventional commits are explicitly the contract.
- A pre-commit hook variant. Only `commit-msg` is supported — it's
  the correct event for message rewriting.
- A plugin-owned opt-in flag. `enabledPlugins` is the only opt-in;
  the plugin does not introduce a parallel surface.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: rewrite CLAUDE.md for the enabledPlugins opt-in model"
```

---

## Task 10: Rewrite DESIGN.md

**Files:**
- Modify: `DESIGN.md`

- [ ] **Step 1: Update the "Last updated" line and "Problem" sections (unchanged)**

Open `DESIGN.md`. Change line 6:

Old: `Last updated: 2026-05-18.`
New: `Last updated: 2026-05-19.`

Lines 8–31 ("Problem" through "What it does not need") stay as-is.

- [ ] **Step 2: Replace "Opt-in model" section**

Replace lines 33–73 (the entire "Opt-in model" section, including
the "Settings path: pluginConfigs slot" subsection) with:

```markdown
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
```

- [ ] **Step 3: Replace "Materialization" section**

Replace lines 75–98 (the "Materialization" section) with:

```markdown
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
```

- [ ] **Step 4: Delete the "Why slash commands do not invoke the bash scripts" section**

Delete lines 100–120 (the entire section, including the "Whether
Edit/Write surface a normal tool-permission prompt depends on…"
and "install-hook.sh / uninstall-hook.sh remain in the repo for…"
paragraphs). It is moot — the one remaining slash command does
shell out to its bash script, with sandbox bypass auto-approved.

- [ ] **Step 5: Add "The disable asymmetry" section before "Requirements this design meets"**

Insert the following just before the `## Requirements this design meets` header (which was at line 122 in the original file):

```markdown
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
```

- [ ] **Step 6: Update "Safety rules" section (line ~136 in the original) — unchanged content, but check it does not still mention the flag**

Read lines around "Safety rules" and confirm none of the bullets
mention the flag, `pluginConfigs`, or the teardown branch. If any
do, edit them out. The four safety-rule bullets (marker-based
idempotence, lowercase-only conventional prefixes, already-emoji
detection, merge/squash/amend skipping) are all hook-body
properties and should be unchanged.

- [ ] **Step 7: Rewrite "Dependencies" section**

Replace lines 150–154 with:

```markdown
## Dependencies

No runtime dependencies beyond bash and git. `jq` was previously
required at runtime to read and edit `.claude/settings.json`; with
the flag gone, the materializer and uninstall script no longer
parse JSON. `jq` is still used by `just precommit` to validate
manifest JSON, but that is a development concern only.
```

- [ ] **Step 8: Rewrite "Decomposition" section**

Replace lines 156–182 (the "Decomposition" section) with:

```markdown
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
```

- [ ] **Step 9: Update "Open questions" section if needed**

The original question "Should `gitmoji.cfg` be editable without
forking?" remains valid. The other question ("Could the
materializer do anything useful when Claude Code is opened on a
non-git directory? Currently it silently exits. Probably fine.")
is still accurate. Leave the section as-is unless the user wants
changes.

- [ ] **Step 10: Commit**

```bash
git add DESIGN.md
git commit -m "docs: rewrite DESIGN for enabledPlugins-based opt-in"
```

---

## Task 11: Rewrite README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the "Installation" section (lines 24–75)**

Replace the `## Installation` section and the `### Opt-in scopes`
subsection with:

```markdown
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
to `rm .git/hooks/{commit-msg, gitmoji.sh, gitmoji.cfg}` (skips
the marker check — only do this if you're sure those files came
from gitmoji).
```

- [ ] **Step 2: Update "Dependencies" section (lines 104–107)**

Replace with:

```markdown
## Dependencies

`bash` and `git`. No `jq` at runtime — the materializer and
uninstall script are pure shell with no JSON parsing.
```

- [ ] **Step 3: Sanity-check the prefix table** is unchanged (it
should be; nothing in this design touched the mapping).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for the enabledPlugins opt-in model"
```

---

## Task 12: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run precommit checks**

```bash
just precommit
```

Expected:
- JSON validation passes for `plugin.json` and `hooks.json`.
- Shellcheck passes for all scripts.
- Prints `ok`.

- [ ] **Step 2: Run the hook smoke test**

```bash
just test
```

Expected: `input: feat: add a thing` → `output: ✨ add a thing`.

- [ ] **Step 3: Run integration tests**

```bash
just test-integration
```

Expected: `PASS` for both `tests/materialize.sh` and
`tests/uninstall.sh`.

- [ ] **Step 4: Self-test the plugin via --plugin-dir**

This catches issues where the plugin cache lags the working tree
(per memory `feedback_plugin_self_test`).

```bash
work="$(mktemp -d)"
cd "$work"
git init -q
claude --plugin-dir /Users/david/code/gitmoji --add-dir "$work" --add-dir /Users/david/code/gitmoji -p "what is 2+2"
ls -la .git/hooks/
```

Expected: `.git/hooks/commit-msg`, `gitmoji.sh`, `gitmoji.cfg` all
exist; `commit-msg` and `gitmoji.sh` are executable; `commit-msg`
contains the `gitmoji-plugin-installed` marker.

Clean up:

```bash
cd /Users/david/code/gitmoji
rm -rf "$work"
```

- [ ] **Step 5: Verify the current repo's commit-msg hook still works**

The implementation steps will have triggered multiple SessionStart
materializations against this repo. Confirm the hook works for the
upcoming release commit (per memory
`feedback_verify_commit_msg_hook_before_release`):

```bash
echo "test: verify hook" > /tmp/gitmoji-verify-msg
.git/hooks/commit-msg /tmp/gitmoji-verify-msg
cat /tmp/gitmoji-verify-msg
rm /tmp/gitmoji-verify-msg
```

Expected output: `✅ verify hook` (the `test:` prefix maps to ✅).

- [ ] **Step 6: Surface release readiness to the user**

Stop here. Do **not** run `just release` — that's the user's call.
Tell the user that the plan is complete, the working tree is
clean, and the next step is a minor version bump via `just release
minor` (semver minor because this is a breaking change in opt-in
semantics, per the spec).

---

## Self-review checklist

After completing all tasks, the reviewer should be able to confirm:

- The string `pluginConfigs` appears nowhere in `scripts/`,
  `commands/`, `hooks/`, `CLAUDE.md`, `DESIGN.md`, `README.md`,
  `tests/`. (It may appear in `docs/` historical artifacts and in
  `plugin-dev/` vendored toolkit — both are expected.)
- The string `enabledPlugins` appears in `CLAUDE.md`, `DESIGN.md`,
  and `README.md`.
- `scripts/install-hook.sh`, `commands/install.md`, and
  `tests/install.sh` are gone from the working tree.
- `just precommit` and `just test-integration` pass.
- `/gitmoji:install` is no longer available; `/gitmoji:uninstall`
  shells to `scripts/uninstall-hook.sh` with sandbox bypass.
