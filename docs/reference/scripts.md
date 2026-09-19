---
type: Reference
title: Harness Scripts
description: Behavior contract of every script under scripts/ — what it does, what it writes, and what it prints.
status: current
last_modified: 2026-09-20
tags: [scripts, reference]
sources: [scripts]
---

# Harness Scripts

All scripts are bash, `set -euo pipefail`, and safe to re-run.

## scripts/

### `setup-repo.sh <[org/]repo>`

Imports a GitHub repository into the lab. Clones into `repos/<repo>/` on
first run; on later runs fetches and fast-forwards the default branch.
If the repo ships `scripts/setup-hooks.sh`, runs it once at the base
clone — linked worktrees share the common git dir, so hooks need no
per-worktree install. Prints the absolute repo path.

### `create-worktree.sh [--detach] <[org/]repo> <name>`

Creates `worktree/<repo>/<name>` based on `origin/main` — on a new branch
named `<name>` by default, or on a detached HEAD when `--detach` is given
(used for dispatched task worktrees; no branch is named before the task
is understood). Calls `setup-repo.sh` internally (clone-or-update), then
symlinks this harness's `scripts/hooks/` into the managed repo's git
dir — a repo's own hooks are never clobbered. Prints the absolute
worktree path — use it for all edits.

### `spawn-repo-agent.sh [--kind <kind>] [--no-sandbox] <[org/]repo> -- <task>`

Dispatches a task to a dedicated worker agent via herdr. Creates a
collision-free task worktree (`worktree/<repo>/task/<uuid>`, detached HEAD
at `origin/main`), reuses or creates the repo's herdr workspace + tab,
launches the agent (sandboxed by default via
`scripts/lib/sandbox-wrap.sh`), and submits the task with a self-naming
preamble. Prints `Dispatched to pane <pane_id>` — keep the pane id for
monitoring. See `orchestration.md`.

### `append-pr-log.sh <owner>/<repo> <pr-number> <worktree-path>`

Appends the worktree's latest commit as a collapsed `<details>` entry under
`## Decision Logs` in the PR body. Used to keep an audit trail on stacked
PRs.

### `setup-hooks.sh`

Installs every hook in `scripts/hooks/` as a symlink into the common git
dir. Links resolve to the base clone's `scripts/hooks/`, so they keep
working when a worktree is removed; `setup-repo.sh` invokes this
automatically for repos that ship it.

### `lint.sh`

Runs shellcheck over every tracked shell file (`*.sh` plus the
extension-less git hooks). Prefers the portable, gitignored
`tools/shellcheck` install; falls back to shellcheck on PATH.

### `check-docs-stale.sh [base-ref]`

Enforces the docs freshness contract: every `docs/design`/`docs/reference`
doc declares the files it is derived from in its `sources:` frontmatter.
Fails when a declared source path no longer exists (`MISSING`), or when a
source changed in `base...HEAD` (default `origin/main`) without the doc
changing in the same diff (`STALE`). `docs/adr/` is exempt — ADRs are
point-in-time records.

### `check-test-coverage.sh`

Fails when any `scripts/*.sh` lacks a matching `tests/scripts/test-<name>.sh`.
Run by the `pre-push` git hook and as the last step of the CI
`shell-test` job.

## scripts/hooks/

| Hook | Behavior |
|---|---|
| `pre-commit` | Blocks commits to `main` and to branches whose PR is already merged/closed |
| `pre-push` | PR-workflow reminders; blocks the push when `scripts/check-test-coverage.sh` exists and reports a script without a test |

## scripts/lib/

### `rm-guard.sh`

Shared by every agent guard hook. Provides the unconditional
dangerous-`rm` blocklist (recursive deletes of `$HOME`, `/`, `/home`,
`/etc`, `/usr`, `/var`, …, including `sudo` and glob forms) and
`load_allowed_ext_dirs`, which reads `ALLOWED_EXT_DIRS` from a given `.env`.

### `hook-common.sh`

Shared core for the per-agent `PreToolUse` guard hooks. Resolves the
script root (from the hook path) and the harness root (walk-up to the
nearest `repos/` + `worktree/` ancestor), runs the command-token and
path-list guard checks, builds the allowlist (`known_agent_dirs` —
every supported agent's own config dir — plus `ALLOWED_EXT_DIRS` from
both roots' `.env`), and
emits each agent kind's deny JSON (claude/codex `permissionDecision`,
agy `deny`, devin `block`). The files under `.<agent>/hooks/` are thin
adapters supplying only the agent kind and stdin JSON field names;
`hook_main_command` / `hook_main_file` run the full stdin→decision flow.

### `sandbox-wrap.sh`

Builds the bubblewrap command line that confines a spawned worker to its
worktree — agent-agnostic mount-namespace isolation. See `sandbox.md` for
the permission model. `sandbox_wrap_cmd <worktree> <kind> <argv...>`
prints a quoted `bwrap ... -- <argv>` command; returns 3 when `bwrap` is
missing so callers fail closed.
