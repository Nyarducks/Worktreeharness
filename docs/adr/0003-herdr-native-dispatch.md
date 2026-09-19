---
type: ADR
title: Dispatch workers through herdr-native workspaces/tabs/panes
description: One herdr workspace per repo, one tab per task, worker spawned in the tab's root pane.
status: accepted
last_modified: 2026-09-20
tags: [herdr, dispatch, orchestrator]
---

# ADR-0003: Dispatch workers through herdr-native workspaces/tabs/panes

## Status

Accepted

## Context

An earlier design wrapped herdr with custom ownership/reporting scripts
(`lib/herdr-report.sh`, `lib/worktree-ownership.sh`). It duplicated state
herdr already tracks and broke whenever herdr's model evolved.

## Decision

Dispatch maps directly onto herdr's native model: one workspace per repo
(matched by label), one tab per task, the worker agent in the tab's root
pane. Workers carry no reporting protocol — monitoring is pull-based
(`herdr agent wait`, `herdr agent read`, `herdr agent prompt`). Workers
are spawned with `cwd = worktree` so the target repo's own `AGENTS.md` and
`.agents/skills` load; workers never learn that the harness exists.

## Consequences

- No harness-side state to keep in sync; `spawn-repo-agent.sh` is a thin
  composition of `create-worktree.sh` + herdr commands.
- Follow-ups and inspection go through standard herdr commands.
- Requires the herdr CLI and an active session. (The in-process
  `/parallel-worktree` fallback was removed — see ADR-0008.)
