---
type: Reference
title: Harness Scripts
description: Behavior contract of every script under scripts/ — what it does, what it writes, and what it prints.
status: current
author: Devin
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
Prints the absolute repo path.

### `create-worktree.sh <[org/]repo> <branch>`

Creates `worktree/<repo>/<branch>` on a new branch based on
`origin/main`. Calls `setup-repo.sh` internally when the repo is not yet
imported. Prints the absolute worktree path — use it for all edits.

### `spawn-repo-agent.sh [--kind <kind>] [--no-sandbox] <[org/]repo> -- <task>`

Dispatches a task to a dedicated worker agent via herdr. Creates a
collision-free task worktree (`worktree/<repo>/task/<uuid>`), reuses or
creates the repo's herdr workspace + tab, launches the agent (sandboxed by
default via `scripts/lib/sandbox-wrap.sh`), and submits the task with a
self-naming preamble. Prints `Dispatched to pane <pane_id>` — keep the
pane id for monitoring. See `orchestration.md`.

### `append-pr-log.sh <owner>/<repo> <pr-number> <worktree-path>`

Appends the worktree's latest commit as a collapsed `<details>` entry under
`## Decision Logs` in the PR body. Used to keep an audit trail on stacked
PRs.

### `setup-hooks.sh`

Installs the git hooks in `scripts/hooks/` as symlinks into the common git
dir. Safe to run from the base repo or any worktree.

## scripts/hooks/

| Hook | Behavior |
|---|---|
| `pre-commit` | Blocks commits to `main` and to branches whose PR is already merged/closed |
| `pre-push` | Additional push-time checks |

## scripts/lib/

### `rm-guard.sh`

Shared by every agent guard hook. Provides the unconditional
dangerous-`rm` blocklist (recursive deletes of `$HOME`, `/`, `/home`,
`/etc`, `/usr`, `/var`, …, including `sudo` and glob forms) and
`load_allowed_ext_dirs`, which reads `ALLOWED_EXT_DIRS` from a given `.env`.

### `sandbox-wrap.sh`

Builds the bubblewrap command line that confines a spawned worker to its
worktree — agent-agnostic mount-namespace isolation. See `sandbox.md` for
the permission model. `sandbox_wrap_cmd <worktree> <kind> <argv...>`
prints a quoted `bwrap ... -- <argv>` command; returns 3 when `bwrap` is
missing so callers fail closed.
