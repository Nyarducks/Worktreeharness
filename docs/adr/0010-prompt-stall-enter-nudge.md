---
type: ADR
title: Recover stalled prompt submits with a real Enter keypress
description: On agent_prompt_stalled after `herdr agent prompt`, spawn-repo-agent.sh sends `pane send-keys <pane> Enter` and re-waits; other failure modes are never nudged.
status: accepted
last_modified: 2026-09-29
tags: [herdr, dispatch, orchestrator]
---

# ADR-0010: Recover stalled prompt submits with a real Enter keypress

## Status

Accepted

## Context

`herdr agent prompt` claims an atomic paste+Enter, but TUI agents using
bracketed paste can swallow the trailing Enter — the pasted prompt sits
in the input unsubmitted while herdr's fixed 5s stall window reports
`agent_prompt_stalled`. Observed with devin: every dispatch ended with
the human pressing Enter by hand, and the orchestrator's "submission
was not confirmed" warning fired on what was actually a delivered
prompt.

## Decision

On `agent_prompt_stalled` or caller `timeout` after `herdr agent
prompt`, `spawn-repo-agent.sh` sends a real keypress —
`herdr pane send-keys <pane> Enter` — then re-waits for
`working`/`blocked`/`done`. Verified against a live devin pane:
`pane send-text` + `pane send-keys Enter` submits with zero human
intervention.

Alternatives rejected:

- **Nudge unconditionally or on every failure** — a stray Enter could
  accept a blocked agent's permission prompt; only stall/timeout
  outcomes get the nudge.
- **`send-text` + `send-keys` as the submission path** — `agent prompt`'s
  paste is atomic and race-free; keep it for submission and use
  `send-keys` only as the recovery nudge.
- **Wait for a herdr-side fix** — the correct fix is upstream (emit
  Enter outside the bracketed paste), but the harness should not block
  on a herdr release cadence; once upstream is fixed the recovery path
  simply never triggers.

## Consequences

- Dispatches self-recover from the swallowed-Enter failure; the
  "submission was not confirmed" warning now means something real
  broke.
- The nudge is one extra keypress on the stall path only — clean
  submissions are unchanged.
