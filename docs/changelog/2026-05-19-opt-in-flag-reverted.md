# 2026-05-19 — Opt-in flag reverted to `enabledPlugins`

An earlier design used a bespoke plugin-owned flag
(`pluginConfigs["gitmoji@ddaanet"].options.enabled`) for per-repo
opt-in on top of a globally-enabled plugin. That two-lever model was
dropped in favor of `enabledPlugins["gitmoji@ddaanet"]` alone: the
bespoke flag duplicated `enabledPlugins`, ran afoul of Claude Code's
auto-mode classifier hard-blocking agent edits to
`.claude/settings.json`, and produced a footgun where a
more-specific override layer could silently tear down a working hook
on SessionStart.

CLAUDE.md, DESIGN.md, and README.md were rewritten in the same commit
to describe the `enabledPlugins`-only model.
