# Contributing

Development rules for Worktreeharness. The non-negotiables live in
`AGENTS.md`; this file covers how to work.

## Worktree workflow

All changes happen in a worktree under `worktree/` — create one before
editing:

```bash
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
```

Base clones under `repos/` are never edited. See
`docs/design/overview.md` for the layout.

## Git workflow

- Feature branch + PR; never commit to `main`
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`
- The pre-commit hook blocks `main` and already-merged/closed PR branches
- Humans approve and merge PRs — agents never do

## Tests

Shell tests live in `tests/`. Run them before pushing:

```bash
bash tests/test-hooks.sh     # guard-hook allow/deny matrix
bash tests/test-sandbox.sh   # bwrap sandbox confinement
```

Hook changes must extend `test-hooks.sh` (it simulates each agent's stdin
JSON protocol). Sandbox changes must extend `test-sandbox.sh`.

## Documentation

Docs are part of every change:

- **`docs/design/`** — design docs in Google OKF v0.2 (markdown + YAML
  frontmatter; `type`, `title`, `description`, `status`,
  `last_modified`, `sources`). Design docs capture intent and invariants
  (What/Why/How at the design level), not implementation detail. Update
  the relevant doc in the same commit as any behavior change.
- **`docs/reference/`** — fact inventories (config tables, script/skill
  lists). Same frontmatter convention with `type: Reference`.
- **`docs/adr/`** — record significant decisions as
  `docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences, OKF
  frontmatter `type: ADR`). Numbers are sequential.
- **`README.md`** — quick start only; keep it slim.
- **`AGENTS.md`** — must-follow rules only; do not document structure or
  usage there.
