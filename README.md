# Worktreeharness

A Claude Code harness for worktree-driven multi-repository development. All code changes flow through isolated `git worktree` checkouts — the base repository is never edited directly. Claude Code hooks enforce this automatically.

---

## How it works

```
Worktreeharness/
├── repos/<repo>/          # Base clone — never edited directly
├── worktree/<repo>/<branch>/  # Active worktree — all edits happen here
├── scripts/               # Harness management scripts
└── .claude/               # Claude Code hooks and skills
```

1. `scripts/setup-repo.sh` clones (or fast-forwards) a GitHub repo into `repos/`.
2. `scripts/create-worktree.sh` branches from `origin/main` and creates an isolated checkout under `worktree/`.
3. Claude Code's `PreToolUse` hooks block any `Edit`/`Write` outside `worktree/`, ensuring the base clone stays clean.
4. Work is committed and pushed from the worktree, then a PR is opened against the original repository.

Both `repos/` and `worktree/` are gitignored — they are ephemeral working directories, not project files.

---

## Requirements

| Tool | Purpose | Install |
|---|---|---|
| `git` ≥ 2.5 | Worktree support | `sudo apt install git` / `brew install git` |
| `gh` (GitHub CLI) | Clone, PR creation, repo auth | https://cli.github.com |
| `jq` | Hook input parsing | `sudo apt install jq` / `brew install jq` |
| `bash` ≥ 4.0 | Script runtime | Pre-installed on most systems; macOS ships bash 3 — upgrade via `brew install bash` |
| `realpath` | Path normalisation in hooks | Part of GNU coreutils; on macOS install via `brew install coreutils` |
| [Claude Code](https://claude.ai/code) | AI coding assistant that drives this harness | `npm install -g @anthropic-ai/claude-code` |

After installing `gh`, authenticate once:

```bash
gh auth login
```

---

## Setup

### Clone and initialise

```bash
gh repo clone <your-org>/Worktreeharness
cd Worktreeharness
bash scripts/setup-hooks.sh   # installs the pre-commit hook
```

### Optional: set the harness root explicitly

If auto-detection fails (e.g. when running scripts from outside the repo), export:

```bash
export WORKTREE_LAB_DIR="$(git rev-parse --show-toplevel)"
```

---

## Usage

### Develop an external repository

```bash
# 1. Import the repo (clone on first run; pull on subsequent runs)
scripts/setup-repo.sh <owner>/<repo>

# 2. Create a worktree on a new feature branch
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
#    → worktree/<repo>/feat/<topic>/

# 3. Edit files inside the worktree (Claude Code enforces this via hooks)
#    Read/Edit using the absolute path printed by create-worktree.sh

# 4. Commit from the worktree
git -C worktree/<repo>/feat/<topic> add <files>
git -C worktree/<repo>/feat/<topic> commit -m "feat(<scope>): ..."

# 5. Push and open a PR against the original repo
git -C worktree/<repo>/feat/<topic> push -u origin feat/<topic>
gh pr create --repo <owner>/<repo> --head feat/<topic> --title "..."

# 6. Clean up after the PR is merged
git -C repos/<repo> worktree remove ../../worktree/<repo>/feat/<topic>
git -C repos/<repo> branch -d feat/<topic>
```

### Develop this harness itself

```bash
SLUG="$(git remote get-url origin | sed 's|.*github\.com[:/]\(.*\)\.git|\1|')"
scripts/create-worktree.sh "${SLUG}" feat/<topic>
#    → worktree/Worktreeharness/feat/<topic>/
```

Then follow the same commit → push → PR flow above.

### Run multiple tasks in parallel

Create one worktree per independent task. Each has its own branch and working directory but shares `.git` with the base clone.

```bash
scripts/create-worktree.sh <owner>/<repo> feat/task-a
scripts/create-worktree.sh <owner>/<repo> feat/task-b
# Work on both concurrently; the same branch cannot be checked out twice.
```

---

## Claude Code skills

The following slash commands are available inside Claude Code when working in this harness:

| Command | Description |
|---|---|
| `/parallel-worktree` | Full worktree workflow — import repo, create worktree, implement, commit, PR |
| `/git-operations` | Branching, committing, PR creation and editing via `gh` |
| `/pr-review-fix` | Review a PR, post inline comments, auto-fix findings in a worktree |
| `/setup-harness` | Install this framework into a new repo, or onboard an external repo |
| `/herdr-dispatch` | Orchestrator mode — spawn a real Claude Code process via herdr inside a target repo's own worktree |

---

## Orchestrator mode (`/herdr-dispatch`)

`/parallel-worktree` runs work in-process, so a target repo's own `.claude/skills`/`CLAUDE.md` never load — only Worktreeharness's own do, since the process stays rooted at the harness root. When a task spans multiple repos (e.g. an app change plus a matching infra change), or you specifically want a target repo's own conventions to apply, use `/herdr-dispatch` instead: it spawns a *separate* Claude Code process via `herdr`, rooted at that repo's worktree.

```bash
scripts/spawn-repo-agent.sh <owner>/<repo> feat/<topic> -- "<task description>"
```

Dispatched agents report cross-repo needs and completion back to the Orchestrator via `herdr agent send`, using `[CROSS-REPO-REQUEST]` / `[TASK-DONE]` / `[TASK-BLOCKED]` prefixes (see `.claude/skills/herdr-dispatch/SKILL.md`) rather than spawning further agents themselves — the Orchestrator is the single place that dispatches repos, which avoids duplicate worktrees on the same repo+branch.

### Delegated-worktree ownership

Dispatching also creates a local runtime ownership record under
`.runtime/herdr-worktree-ownership/` (ignored by Git). The record remains in
place after a worker reports `[TASK-DONE]` or `[TASK-BLOCKED]`: those messages
are handoffs to the Orchestrator, not permission for it to edit the worker's
worktree. Send follow-up work through the dispatcher instead:

```bash
scripts/spawn-repo-agent.sh <owner>/<repo> feat/<topic> -- "<follow-up task>"
```

Codex and agy write guards deny an Orchestrator write to an owned worktree and
show this command in the denial message. The dispatched worker receives a
scoped `HERDR_WORKER_WORKTREE` marker and is not blocked from working in its
own assigned worktree. Release ownership only when the delegated work is
really finished and no follow-up will be sent:

```bash
scripts/spawn-repo-agent.sh --release <owner>/<repo> feat/<topic>
```

`--release` is an explicit cleanup operation; it does not stop a worker or
remove the worktree. Stop/verify the worker first if it may still be active.

Worker agents' model is controlled by `HERDR_WORKER_MODEL` in `.env` (see `.env.sample`) — `inherit` (default) uses the Orchestrator's own model, or set an explicit model (e.g. `haiku`) to always use that for workers.

Requires the herdr CLI and an active herdr session (`$HERDR_ENV=1`).

---

## Guard hooks

Three `PreToolUse` hooks run automatically inside Claude Code:

| Hook | Triggers on | Effect |
|---|---|---|
| `guard-writes-to-worktree.sh` | `Edit`, `Write` | Denies any write outside `worktree/` and any Orchestrator write to a herdr-owned worktree (unless the target is under `ALLOWED_EXT_DIRS`) |
| `restrict-to-repo-root.sh` | `Read` | Denies reads outside the harness root, `worktree/`, and `repos/` (unless under `ALLOWED_EXT_DIRS`) |
| `guard-bash-commands.sh` | `Bash` | Blocks dangerous `rm` commands unconditionally, and restricts other paths to the harness root or `ALLOWED_EXT_DIRS` |

The Codex equivalents (`.codex/hooks/restrict-to-harness-root.sh`, `.codex/hooks/guard-writes-to-worktree.sh`) enforce the same policy for Codex sessions. All of them share `scripts/lib/rm-guard.sh` for the rm safety net and the `ALLOWED_EXT_DIRS` allowlist logic.

These are configured in `.claude/settings.json` / `.codex/hooks.json` and require no manual activation.

### Allowing access outside the harness root

By default every hook confines Read/Write/Bash access to the harness root (`repos/`, `worktree/`, and the harness's own tracked files). To let commands and file operations reach specific external directories — e.g. Claude Code's own config at `~/.claude`, or scratch files under `/tmp` — copy `.env.sample` to `.env` and set:

```bash
ALLOWED_EXT_DIRS=~/.claude,/tmp
```

`.env` is gitignored; this is a local, per-machine setting. External access is enabled precisely when `ALLOWED_EXT_DIRS` is non-empty, and only for the listed paths — there is no separate flag to bypass the harness-root restriction entirely.

### rm safety net

Independently of `ALLOWED_EXT_DIRS` every hook unconditionally blocks recursive `rm` commands (`rm -rf`, `sudo rm -r`, etc.) whose target resolves to `$HOME`, `/`, an ancestor of `$HOME` (e.g. `/home`), or another critical top-level directory (`/etc`, `/usr`, `/var`, ...), including glob forms like `rm -rf ~/*` that would wipe a directory's contents. This guards against an accidental `rm -rf ~` or `rm -rf /` — especially important when running Claude Code with `--dangerously-skip-permissions`, where hooks are the only remaining safety net.

---

## Git workflow

- **Never commit directly to `main`** — always use a feature branch and open a PR.
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`.
- The `pre-commit` hook blocks commits to `main` and to branches whose PR is already merged or closed.
- Always check a PR is still open before pushing additional commits: `gh pr view <branch> --repo <owner>/<repo>`.
