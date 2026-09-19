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
`docs/design/README.md` for the layout.

## Git workflow

- Feature branch + PR; never commit to `main`
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`
- The pre-commit hook blocks `main` and already-merged/closed PR branches
- Humans approve and merge PRs — agents never do

## Shell script style

Everything under `scripts/` and the hook scripts follows
`docs/reference/shell-style.md`.

## Tests

Shell tests live in `tests/`. Run them before pushing:

```bash
bash tests/test-hooks.sh                    # guard-hook allow/deny matrix
bash tests/test-sandbox.sh                  # bwrap sandbox confinement
for t in tests/scripts/test-*.sh; do bash "$t"; done   # per-script tests
bash scripts/lint.sh                        # shellcheck every shell file
```

`lint.sh` uses `tools/shellcheck` when present (portable install,
gitignored — see its error message for the one-line install), otherwise
shellcheck from PATH.

Hook changes must extend `test-hooks.sh` (it simulates each agent's stdin
JSON protocol). Sandbox changes must extend `test-sandbox.sh`. Any change
to `scripts/*.sh` must extend the matching `tests/scripts/test-*.sh` —
stubs for `gh`/`herdr`/`bwrap` live in `tests/scripts/lib.sh`. The
`scripts/*.sh` → `tests/scripts/test-*.sh` pairing is enforced by the
`pre-push` hook and the CI `shell-test` job via
`scripts/check-test-coverage.sh`. CI (`.github/workflows/ci.yaml`) runs
all suites on PRs that touch `*.sh`, plus a `docs-freshness` gate on
every PR. Dependabot (`.github/dependabot.yml`) opens weekly PRs for
GitHub Actions updates — actions are pinned to a major (`@v6`) and
runners to `ubuntu-24.04` so upstream deprecations arrive as reviewable
PRs, not warnings.

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
  frontmatter `type: ADR`). Numbers are sequential. ADRs are immutable
  point-in-time records — never edit one to track code drift; write a
  new ADR when a decision is revisited.
- **`README.md`** — quick start only; keep it slim.
- **`AGENTS.md`** — must-follow rules only; do not document structure or
  usage there.

### Keeping docs fresh

Docs rot when prose claims drift from code. Three mechanisms prevent it:

- **`sources:` contract** — every design/reference doc *derived from
  code* lists the files it is derived from. `scripts/check-docs-stale.sh`
  (CI: `docs-freshness`) fails a PR that changes a source without
  touching its doc, or that leaves a `sources` entry pointing at a
  deleted/renamed path. Keep `sources` as narrow as the doc's actual
  dependencies. Prescriptive docs (conventions like `shell-style.md`)
  leave `sources: []` — the check skips them.
- **Write checkable claims** — avoid universal quantifiers over
  code-derived facts ("every agent implements …") and embedded counts
  ("28 checks") unless a test asserts them; enumerate the matrix or name
  the exception instead.
- **Root docs carry no `sources:`** — `README.md`/`AGENTS.md`/
  `CONTRIBUTING.md` are reviewed by hand: re-check the quick start and
  the rule list whenever workflow routing or skill behavior changes.
