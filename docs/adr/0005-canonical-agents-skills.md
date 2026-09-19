---
type: ADR
title: Canonical .agents/skills with per-agent config directories
description: One skills directory shared by all agents; each agent keeps its own hooks config format.
status: accepted
last_modified: 2026-09-20
tags: [skills, agents, config]
---

# ADR-0005: Canonical `.agents/skills` with per-agent config directories

## Status

Accepted

## Context

Four agent CLIs are supported and each reads a different config location.
Duplicating skills per agent drifted immediately. Claude Code does not
support a standalone `.claude/hooks.json` (only `settings.json`), and
Devin expects `hooks.v1.json` — formats are not interchangeable.

## Decision

`.agents/skills/` is the single canonical skills directory — Codex,
Devin, and Antigravity read it natively; `.claude/skills` is a symlink to
it so Claude Code sees the same set. `AGENTS.md` is the canonical agent
doc; `CLAUDE.md` contains only `@AGENTS.md`. Each agent keeps hooks in its
own directory and native format (`.claude/settings.json`,
`.codex/hooks.json`, `.agents/hooks.json`, `.devin/hooks.v1.json`), with
the same three policies implemented per format.

## Consequences

- One place to edit skills; zero drift.
- Four hook implementations to keep in sync — mitigated by
  `tests/test-hooks.sh`, which simulates each agent's stdin JSON format.
- `.agents/hooks.json` cannot collide: no other supported agent reads
  `.agents/` for hooks.
