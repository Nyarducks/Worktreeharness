---
type: ADR
title: Workers rename their own agent and tab
description: The dispatcher uses a w-<uuid> placeholder; the worker picks a task-derived name via herdr after reading the prompt.
status: accepted
last_modified: 2026-09-20
tags: [herdr, naming, worker]
---

# ADR-0004: Workers rename their own agent and tab

## Status

Accepted

## Context

The dispatcher cannot derive a meaningful agent name before the task is
understood — generated names like `w-<repo>-<uuid>` are meaningless to the
human watching herdr. Only the worker knows what the task actually is.

## Decision

Agents spawn under the placeholder `w-<uuid>`. The initial prompt embeds
a preamble instructing the worker to run `herdr agent rename <pane>
<slug>` and `herdr tab rename <tab> <title>` once it understands the task.
Pane/tab ids are injected as literal values; `HERDR_*` environment
variables are also present inside the pane. If a worker skips the rename,
it is still addressable by pane id.

## Consequences

- Meaningful tab labels appear without the dispatcher parsing the task.
- Adds one responsibility to the worker prompt — kept short and
  self-contained so the worker needs no harness knowledge.
