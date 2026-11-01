## Remaining

- After pushing `main`, check that a credential-less clone populates `memory/` (`ddaanet/gitmoji-memory` is public and clones keyless with its tier): `HOME="$TMPDIR/anon" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git -c credential.helper= clone --recurse-submodules https://github.com/ddaanet/gitmoji.git "$TMPDIR/anon-clone"`.
- Curate the `ddaanet` tier index from another repo: tier lines alone are ~24.5 KB, so the root `memory/MEMORY.md` (26,094 B) stays past the ~24,985 B loader cutoff and gitmoji's own facts load truncated.
