# AGENTS.md — Worktreeharness

Worktree-driven multi-repository development harness.

## Which workflow

- **Developing Worktreeharness** — the task targets *this* repository:
  use `worktreeharness-development`. Create the worktree yourself with
  `scripts/create-worktree.sh` and work in it directly.
- **Working on any other repository** — use `worktree-development`.
  Dispatch a worker via herdr — never edit other repos in-process. If the
  request does not say which agent kind or which repository, ask the user
  before dispatching.

## Rules — always follow

1. **Edit only inside `worktree/`** — create a worktree first
   (`scripts/create-worktree.sh`), never edit `repos/` directly.
2. **Never commit to `main`** — feature branch + PR. Never approve or
   merge a PR; the human does.
3. **Never edit a delegated worktree** — a worktree assigned to a
   dispatched worker belongs to that worker; send follow-ups to it via
   herdr instead.
4. **Keep docs current** — update `docs/design/` in the same commit as any
   behavior change; record significant decisions as ADRs in `docs/adr/`.
   CI enforces the doc↔code link via each doc's `sources:` frontmatter.

## Pointers

- How to work here: `CONTRIBUTING.md`
- Architecture and design docs: `docs/design/`
- Decision records: `docs/adr/`
