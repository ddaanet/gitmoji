## Brief: teach the SessionStart message not to invite a second emoji

2026-07-27

Origin: a `/ddaa:proof` pass over gitlore's local memory. A memory file existed
to warn agents about a gitmoji failure mode. It is being deleted, because the
warning belongs in the message the plugin already injects into every session.

### Decisions

- **Add a no-emoji-of-your-own clause** to the `additionalContext` string in
  `scripts/session-materialize.sh`. Proposed wording for the `current` branch
  (line 99):

  > gitmoji's commit-msg hook is installed in this repository. Write
  > `type: subject` — conventional prefix, **no emoji of your own**; the hook
  > adds one, and a leading emoji you type survives into the subject.

- **Fix the `refreshed` branch** (line 92). It currently says only that the
  hook was refreshed — an agent starting there is never told that a
  conventional prefix is required or that emoji are added. It needs the same
  convention sentence as `installed` and `current`.

- **Hoist the shared wording.** Three of the four branches restate the
  convention in slightly different words. One constant, interpolated, keeps
  them from drifting further.

- **Do not document the mapping table or the prefix list** in the message.
  `gitmoji.sh` already prints the full sorted list from the live `gitmoji.cfg`
  on any bad prefix — correct by construction, at the moment of failure. A copy
  in the message would be a second source that rots. (The deleted memory's copy
  had already rotted: it listed 5 of 13 mappings and omitted `release`.)

### Constraints

- `additionalContext` is model-only; `systemMessage` is user-only. The clause
  is for the agent, so it goes in `additionalContext` — the second argument to
  `emit_hook_output`.
- Both strings pass through `json_escape`; keep the wording free of anything
  that would complicate that.
- This is always-on context in every session in every repo where the plugin is
  installed. It must stay short. One clause, not a paragraph.

### Rejected approaches

- **Record it as a memory.** That is what existed, in gitlore's store, and it
  is being deleted: a memory is fetched only if recall happens to select it,
  whereas this hook message is already in context at the moment of writing a
  commit. Prevention at the source beats a recorded incident.
- **Also document the silent-passthrough cases** (`MERGE_HEAD`, `SQUASH_MSG`,
  `CHERRY_PICK_HEAD`, `REVERT_HEAD`, and `fixup!`/`squash!`/`amend! `
  subjects, all of which exit 0 without rewriting). Correct behaviour, no
  incident behind it, and it would cost more context than the confusion it
  prevents.

### Additional context

The failure mode, verified against the installed hook on 2026-07-27:

`gitmoji.sh` guards against double-rewriting by skipping any message whose
first line *starts with* a known emoji. That guard checks position 0 only. A
subject like `test: 🧪 add coverage` starts with `test:`, so the guard does not
fire, the prefix is replaced, and the emoji the author typed is carried into
the rest — producing `✅ 🧪 add coverage`. The commit succeeds and nothing is
reported. Observed in gitlore's history.

Relevant lines in `scripts/session-materialize.sh`: `emit_hook_output` at 44,
and the four branches at 56 (foreign hook present), 85 (installed), 91
(refreshed), 97 (current).
