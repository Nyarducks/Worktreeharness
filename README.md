# Worktreeharness

A Claude Code harness for worktree-driven multi-repository development. All code changes flow through isolated `git worktree` checkouts — the base repository is never edited directly. Claude Code hooks enforce this automatically.

---

## How it works

```
Worktreeharness/
├── repos/<repo>/          # Base clone — never edited directly
├── worktree/<repo>/<branch>/  # Active worktree — all edits happen here
├── scripts/               # Harness management scripts
├── .agents/               # Canonical skills + Antigravity hooks/settings
├── .claude/               # Claude Code settings; skills → symlink to .agents/skills
├── .codex/                # Codex hooks
└── .devin/                # Devin CLI hooks (hooks.v1.json)
```

1. `scripts/setup-repo.sh` clones (or fast-forwards) a GitHub repo into `repos/`.
2. `scripts/create-worktree.sh` branches from `origin/main` and creates an isolated checkout under `worktree/`.
3. `PreToolUse` hooks block any write outside `worktree/`, ensuring the base clone stays clean.
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

## Skills

Skills live canonically in `.agents/skills/` — Codex, Devin, and Antigravity read that directory natively, and `.claude/skills` is a symlink to it so Claude Code sees the same set. The following slash commands are available when working in this harness:

| Command | Description |
|---|---|
| `/parallel-worktree` | Full worktree workflow — import repo, create worktree, implement, commit, PR |
| `/git-operations` | Branching, committing, PR creation and editing via `gh` |
| `/pr-review-fix` | Review a PR, post inline comments, auto-fix findings in a worktree |
| `/setup-harness` | Install this framework into a new repo, or onboard an external repo |
| `/herdr-dispatch` | Spawn a separate agent process via herdr bound to a fresh repo worktree |

---

## Dispatch mode (`/herdr-dispatch`)

`/parallel-worktree` runs work in-process rooted at the harness root, so a target repo's own `.agents/skills` and `AGENTS.md` never load. `scripts/spawn-repo-agent.sh` instead spawns a separate agent process via `herdr`:

```bash
scripts/spawn-repo-agent.sh <owner>/<repo> -- "<task description>"
scripts/spawn-repo-agent.sh --kind agy <owner>/<repo> -- "<task description>"
```

It creates a collision-free worktree (`worktree/<repo>/task/<uuid>` on branch `task/<uuid>`), reuses or creates the repo's herdr workspace (one workspace per repo, one tab per task), and starts the agent there with the worktree as cwd — so the repo's own skills and conventions apply, and the worker knows nothing about this harness.

Monitoring is pull-based: `herdr agent wait <pane> --until idle` to wait for completion, `herdr agent read <pane>` to inspect output, and `herdr agent prompt <pane> "<follow-up>"` to send more work to the same agent.

Requires the herdr CLI and an active herdr session (`$HERDR_ENV=1`).

---

## Guard hooks

The same three `PreToolUse` policies run under every supported agent, each in that agent's own config format:

| Config file | Agent | Tool matchers |
|---|---|---|
| `.claude/settings.json` | Claude Code | `Read`, `Edit\|Write`, `Bash` |
| `.codex/hooks.json` | Codex | `Bash`, `apply_patch` |
| `.agents/hooks.json` | Antigravity | `view_file`, `replace_file_content\|write_to_file\|multi_replace_file_content`, `run_command` |
| `.devin/hooks.v1.json` | Devin CLI | `read`, `write\|edit\|notebook_edit\|apply_patch`, `exec` |

| Hook | Effect |
|---|---|
| `guard-writes-to-worktree.sh` | Denies any write outside `worktree/` (unless the target is under `ALLOWED_EXT_DIRS`) |
| `restrict-to-repo-root.sh` | Denies reads outside the harness root, `worktree/`, and `repos/` (unless under `ALLOWED_EXT_DIRS`) |
| `guard-bash-commands.sh` | Blocks dangerous `rm` commands unconditionally, and restricts other paths to the harness root or `ALLOWED_EXT_DIRS` |

Each agent's scripts live under `<dir>/hooks/` and all share `scripts/lib/rm-guard.sh` for the rm safety net and the `ALLOWED_EXT_DIRS` allowlist logic. No manual activation is needed.

### Allowing access outside the harness root

By default every hook confines Read/Write/Bash access to the harness root (`repos/`, `worktree/`, and the harness's own tracked files). To let commands and file operations reach specific external directories — e.g. Claude Code's own config at `~/.claude`, or scratch files under `/tmp` — copy `.env.sample` to `.env` and set:

```bash
ALLOWED_EXT_DIRS=~/.claude,/tmp
```

`.env` is gitignored; this is a local, per-machine setting. Hooks read `.env` from both the checkout root and the lab root (the directory holding `repos/` and `worktree/`), combining the lists — a single `.env` at the lab root covers every checkout. External access is enabled precisely when `ALLOWED_EXT_DIRS` is non-empty, and only for the listed paths — there is no separate flag to bypass the harness-root restriction entirely.

### rm safety net

Independently of `ALLOWED_EXT_DIRS` every hook unconditionally blocks recursive `rm` commands (`rm -rf`, `sudo rm -r`, etc.) whose target resolves to `$HOME`, `/`, an ancestor of `$HOME` (e.g. `/home`), or another critical top-level directory (`/etc`, `/usr`, `/var`, ...), including glob forms like `rm -rf ~/*` that would wipe a directory's contents. This guards against an accidental `rm -rf ~` or `rm -rf /` — especially important when running Claude Code with `--dangerously-skip-permissions`, where hooks are the only remaining safety net.

### Testing the hooks

`tests/test-hooks.sh` simulates each agent's stdin JSON against a sandboxed lab and asserts every hook's allow/deny decision — covering both the split (`<lab>/worktree/<repo>/<branch>`) and unified (checkout = lab root) topologies, plus the `ALLOWED_EXT_DIRS` union and config command resolution:

```bash
bash tests/test-hooks.sh
```

---

## Git workflow

- **Never commit directly to `main`** — always use a feature branch and open a PR.
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`.
- The `pre-commit` hook blocks commits to `main` and to branches whose PR is already merged or closed.
- Always check a PR is still open before pushing additional commits: `gh pr view <branch> --repo <owner>/<repo>`.
