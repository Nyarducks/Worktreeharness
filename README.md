# Worktreeharness

A harness for worktree-driven multi-repository development. All code changes flow through isolated `git worktree` checkouts — the base repository is never edited directly. Guard hooks enforce this in-process; dispatched workers run inside a bubblewrap sandbox.

## Requirements

| Tool | Purpose | Install |
|---|---|---|
| `git` ≥ 2.5 | Worktree support | `sudo apt install git` / `brew install git` |
| `gh` (GitHub CLI) | Clone, PR creation, repo auth | https://cli.github.com |
| `jq` | Hook input parsing | `sudo apt install jq` / `brew install jq` |
| `bash` ≥ 4.0 | Script runtime | Pre-installed; macOS ships bash 3 — `brew install bash` |
| `realpath` | Path normalisation in hooks | GNU coreutils; on macOS `brew install coreutils` |
| `herdr` | Orchestration for dispatched workers | see https://devin.ai |
| `bwrap` | Worker sandbox (fail-closed; `--no-sandbox` opts out) | `sudo apt install bubblewrap` |

**Optional agent CLIs** — at least one needed to dispatch workers (`--kind`):

| Agent | Install | Verified |
|---|---|---|
| [Claude Code](https://claude.ai/code) | `npm install -g @anthropic-ai/claude-code` | - |
| [Devin CLI](https://docs.devin.ai/cli) | https://docs.devin.ai/cli | ✓ |
| [Codex CLI](https://github.com/openai/codex) | `npm install -g @openai/codex` | - |
| [Antigravity](https://antigravity.google) | https://antigravity.google/download | ✓ |

## Setup

```bash
gh repo clone <your-org>/Worktreeharness
cd Worktreeharness
bash scripts/setup-hooks.sh   # installs the pre-commit hook
gh auth login                 # once per machine
```

## Quick start

```bash
# Develop an external repo
scripts/setup-repo.sh <owner>/<repo>
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
# → worktree/<repo>/feat/<topic>/ — edit, commit, push, open a PR

# Or ask the orchestrator to dispatch a worker agent via herdr
scripts/spawn-repo-agent.sh <owner>/<repo> -- "<task description>"
```

## Documentation

| Doc | Contents |
|---|---|
| `docs/design/overview.md` | Why this exists — goal, requirements, high-level architecture |
| `docs/design/orchestration.md` | How to ask the orchestrator to run workers; lifecycle, monitoring, cleanup |
| `docs/design/sandbox.md` | Worker sandbox permission model |
| `docs/design/guard-hooks.md` | Guard-hook policies, `ALLOWED_EXT_DIRS` |
| `docs/reference/` | Fact inventories — agent configs, skills, scripts |
| `docs/adr/` | Architecture decision records |
| `CONTRIBUTING.md` | Development rules |

## Tests

```bash
bash tests/test-hooks.sh
bash tests/test-sandbox.sh
```
