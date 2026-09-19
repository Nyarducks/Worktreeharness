---
type: Reference
title: Agent Skills
description: The slash-command skills shipped in .agents/skills and what each one orchestrates.
status: current
author: Devin
last_modified: 2026-09-20
tags: [skills, workflow]
sources: [.agents/skills]
---

# Agent Skills

Skills live canonically in `.agents/skills/<name>/SKILL.md`. Codex, Devin,
and Antigravity read `.agents/skills` natively; Claude Code sees the same
set via the `.claude/skills` symlink.

| Skill | Purpose |
|---|---|
| `parallel-worktree` | The default development workflow: import/refresh a repo, create an isolated worktree under `worktree/`, implement, commit, push, open a PR. Invoked before any code change. |
| `git-operations` | Git discipline for this harness: clone via `gh`, branch from latest `main`, commit/PR conventions, PATCH-based PR edits. |
| `pr-review-fix` | PR review loop: post findings as GitHub PR comments, fix each finding in a worktree, push the fix commit back to the PR branch. |
| `setup-harness` | Bootstrap the framework into a new base repository, or onboard an external repository under `repos/` for worktree-based development. |
| `herdr-dispatch` | Orchestrator mode: spawn a separate worker agent via herdr in a fresh task worktree — one workspace per repo, one tab per task. See `orchestration.md`. |
| `workflow-shell-test` | Extract testable shell logic from GitHub Actions workflows and cover it with BATS. |

## Design intent

Skills encode *procedures* the orchestrator follows; they assume the
calling agent already sits at the lab root. A dispatched worker does **not**
receive these skills — it only sees the target repo's own `AGENTS.md`,
`.agents/skills`, and conventions.
