---
type: ADR
title: Repo-local guard hooks with dual-root resolution
description: Hooks separate SCRIPT_ROOT (checkout) from lab root (policy boundary); .env is read from both.
status: accepted
last_modified: 2026-09-20
tags: [hooks, security]
---

# ADR-0007: Repo-local guard hooks with dual-root resolution

## Status

Accepted

## Context

The first hook implementation derived paths from `git worktree list`,
which silently resolved to nonexistent paths in the split topology — and,
once invocation was fixed, sourced `scripts/lib/rm-guard.sh` and `.env`
from the lab root even though they live in the checkout. `|| exit 0`
fallbacks turned both failures into silent no-ops: `rm -rf ~` passed.

## Decision

Every hook resolves two roots independently: `SCRIPT_ROOT` via
`git rev-parse --show-toplevel` (the checkout — source of shared libs and
checkout-local `.env`) and the lab root by walking up to the nearest
ancestor containing both `repos/` and `worktree/` (the policy boundary).
`ALLOWED_EXT_DIRS` is read from `.env` in both roots and combined. The
dangerous-`rm` blocklist is unconditional.

## Consequences

- Hooks fire correctly in both split and unified topologies.
- One lab-root `.env` covers all checkouts; checkout-local `.env` still
  works.
- Regression is covered by `tests/test-hooks.sh` (100 checks), which
  simulates each agent's stdin JSON protocol.
