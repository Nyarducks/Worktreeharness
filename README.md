# Worktreeharness

A harness for worktree-driven multi-repository development. All code changes flow through isolated `git worktree` checkouts — the base repository is never edited directly. Guard hooks enforce this in-process; dispatched workers run inside a bubblewrap sandbox.

## Supports

✔ verified · - not yet verified · ✖ not supported

| OS | |
|---|---|
| Linux | ✔ |
| macOS | - |
| Windows | ✖ |

At least one agent CLI is needed to dispatch workers (`--kind`):

| Agent | |
|---|---|
| [Claude Code](https://claude.ai/code) | - |
| [Devin CLI](https://docs.devin.ai/cli) | ✔ |
| [Codex CLI](https://github.com/openai/codex) | - |
| [Antigravity](https://antigravity.google) | - |

## Requirements

| Tool | Purpose | Install |
|---|---|---|
| `git` ≥ 2.5 | Worktree support | `sudo apt install git` / `brew install git` |
| `gh` (GitHub CLI) | Clone, PR creation, repo auth | https://cli.github.com |
| `jq` | Hook input parsing | `sudo apt install jq` / `brew install jq` |
| `bash` ≥ 4.0 | Script runtime | Pre-installed; macOS ships bash 3 — `brew install bash` |
| `realpath` | Path normalisation in hooks | GNU coreutils; on macOS `brew install coreutils` |
| `herdr` | Orchestration for dispatched workers | https://herdr.dev |
| `bwrap` | Worker sandbox (fail-closed; `--no-sandbox` opts out) | `sudo apt install bubblewrap` |

## Quick start

Open your agent CLI in this repo and ask:

> Implement user auth in `myorg/myapp` — add a login endpoint with tests

The orchestrator dispatches a sandboxed worker to do it — it never edits
other repos in-process, and asks which agent kind/repo if you haven't
said. To work on Worktreeharness itself, ask the same way ("fix X in
this repo") — the orchestrator works in its own worktree.

## Documentation

| Doc | Contents |
|---|---|
| [`docs/design/`](docs/design/) | Design docs — start at the directory README |
| [`docs/design/orchestration.md`](docs/design/orchestration.md) | How to ask the orchestrator to run workers; lifecycle, monitoring, cleanup |
| [`docs/design/sandbox.md`](docs/design/sandbox.md) | Worker sandbox permission model |
| [`docs/design/guard-hooks.md`](docs/design/guard-hooks.md) | Guard-hook policies, `ALLOWED_EXT_DIRS` |
| [`docs/reference/`](docs/reference/) | Fact inventories — agent configs, skills, scripts |
| [`docs/adr/`](docs/adr/) | Architecture decision records |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Development rules |
