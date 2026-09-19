---
type: ADR
title: Split harness self-development from dispatched work; detached task worktrees
description: Orchestrator develops Worktreeharness itself in a self-created worktree; all other repos go through herdr dispatch with user-confirmed agent/repo and detached-HEAD worktrees.
status: accepted
last_modified: 2026-09-20
tags: [orchestrator, dispatch, skills, worktree]
---

# ADR-0008: Split harness self-development from dispatched work; detached task worktrees

## Status

Accepted

## Context

Previously `parallel-worktree` let the orchestrator edit any repository
in-process, with `herdr-dispatch` as the "orchestrator mode" alternative.
In practice the split was ambiguous: the orchestrator could silently pick
an agent kind, pick a repository, or do foreign-repo work itself. Task
worktrees also eagerly created `task/<uuid>` branches before the work —
and its name — was known, and the branch-naming convention could never
reach the worker anyway (a dispatched worker knows nothing about the
harness).

## Decision

- **Harness development stays in-process**: when the task targets the
  Worktreeharness repository itself, the orchestrator creates the
  worktree and works in it directly (`worktreeharness-development`,
  formerly `parallel-worktree`; `git-operations` is scoped to this
  workflow).
- **Everything else is dispatched**: work on any other repository always
  goes through `worktree-development` (formerly `herdr-dispatch`). There
  is no in-process fallback — if herdr is unavailable, report it.
- **Ask before dispatch**: when the request does not specify the agent
  kind (`--kind`) or the repository name, the orchestrator asks the user
  via the ask tool — repository by name — instead of defaulting.
- **Detached task worktrees**: `spawn-repo-agent.sh` creates
  `worktree/<repo>/task/<uuid>` on a detached HEAD at `origin/main`
  (`create-worktree.sh --detach`). No branch is named before the task is
  understood; whether/when the worker names a branch is left to the
  worker, since the harness cannot convey that convention to it.
- **Skill set trimmed**: `pr-review-fix` and `setup-harness` are removed.

## Consequences

- `create-worktree.sh` gains a `--detach` flag; `spawn-repo-agent.sh`
  always uses it and no longer prints a `branch=` field.
- `AGENTS.md` carries the routing rule (開発時 vs 運用時) so every agent
  runtime sees it regardless of skill loading.
- Supersedes the fallback note in ADR-0003 (`/parallel-worktree` no
  longer exists) and narrows ADR-0002's "one worktree per task" to
  detached worktrees for dispatched tasks.
- `pr-review-fix` / `setup-harness` workflows are no longer shipped;
  reinstate as skills if needed.
