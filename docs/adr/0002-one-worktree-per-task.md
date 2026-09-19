---
type: ADR
title: One git worktree per task; base clones never edited
description: All edits happen in isolated worktrees under worktree/; repos/ holds read-only base clones.
status: accepted
author: Devin
last_modified: 2026-09-20
tags: [worktree, isolation]
---

# ADR-0002: One git worktree per task; base clones never edited

## Status

Accepted

## Context

Concurrent tasks on shared checkouts collide on branch state, index, and
uncommitted files. Agents need isolation without the cost of full clones.

## Decision

All code changes happen inside a `git worktree` under
`worktree/<repo>/<branch>/`. `repos/<repo>` is a base clone that is never
edited directly. Each dispatched task gets a uuid-suffixed worktree and
branch (`task/<uuid>`) so concurrent dispatches cannot collide.
Repo-local hooks enforce the write boundary for the orchestrator; the
bubblewrap sandbox enforces it for dispatched workers.

## Consequences

- Unlimited parallel tasks per repo at negligible disk cost.
- `repos/` stays clean and safely shareable.
- Requires hooks/sandbox enforcement — convention alone is not enough.
