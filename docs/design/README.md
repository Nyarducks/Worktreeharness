# Design docs

Design documentation in Google OKF v0.2 — markdown body with YAML
frontmatter (`type`, `title`, `description`, `status`, `last_modified`,
`sources`). Update the relevant doc in the same commit as any behavior
change; see `CONTRIBUTING.md`.

| Doc | Contents |
|---|---|
| [architecture.md](architecture.md) | System topology, directory layout, orchestrator/worker roles, dispatch pipeline |
| [orchestration.md](orchestration.md) | How to ask the orchestrator to run workers; lifecycle, monitoring, ownership, cleanup |
| [sandbox.md](sandbox.md) | Worker sandbox permission model — path × access × reason matrix, process isolation, known holes |
| [agent-integrations.md](agent-integrations.md) | Per-agent config dirs (`.claude`/`.codex`/`.agents`/`.devin`), guard-hook policies, `ALLOWED_EXT_DIRS` |
| [skills.md](skills.md) | `.agents/skills` inventory and purpose |
| [scripts.md](scripts.md) | `scripts/` reference — behavior contract of each script |
