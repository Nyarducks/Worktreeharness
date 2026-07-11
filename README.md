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

## Posting PR comments as a bot (GitHub App)

By default `gh` posts under your personal GitHub account. To have Claude post as a bot identity (shown as `<app-name>[bot]` in the GitHub UI), use a **GitHub App installation token**.

### One-time setup

1. Go to **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Name: e.g. `Claude Code`
   - Homepage URL: any value
   - Permissions → **Pull requests: Read & Write**, **Contents: Read**
   - Uncheck "Webhook active"
2. After creation note the **App ID** on the app settings page.
3. Under **Private keys**, click **Generate a private key** and save the `.pem` file outside the repo, e.g. `~/.config/github-apps/claude-code.pem`.
4. Install the App on each target repository: **App settings → Install App → select repo**.
5. Export two environment variables (add to `~/.bashrc` or `~/.zshrc`):

```bash
export GITHUB_APP_ID=<numeric-app-id>
export GITHUB_APP_PRIVATE_KEY_PATH="${HOME}/.config/github-apps/claude-code.pem"
```

### Generating a token

```bash
# Prints a short-lived installation token (~1 hour)
BOT_TOKEN="$(scripts/github-app-token.sh <owner>/<repo>)"

# Use it for any gh api call that should appear as the bot
GITHUB_TOKEN="${BOT_TOKEN}" gh api repos/<owner>/<repo>/pulls/<pr>/comments -X POST ...
```

`scripts/github-app-token.sh` uses only `openssl`, `curl`, and `jq` — no Python or Node packages required.

---

## Claude Code skills

The following slash commands are available inside Claude Code when working in this harness:

| Command | Description |
|---|---|
| `/parallel-worktree` | Full worktree workflow — import repo, create worktree, implement, commit, PR |
| `/git-operations` | Branching, committing, PR creation and editing via `gh` |
| `/pr-review-fix` | Review a PR, post inline comments, auto-fix findings in a worktree |
| `/setup-harness` | Install this framework into a new repo, or onboard an external repo |

---

## Guard hooks

Two `PreToolUse` hooks run automatically inside Claude Code:

| Hook | Triggers on | Effect |
|---|---|---|
| `guard-writes-to-worktree.sh` | `Edit`, `Write` | Denies any write outside `worktree/` |
| `restrict-to-repo-root.sh` | `Read` | Denies reads outside the harness root, `worktree/`, and `repos/` |

These are configured in `.claude/settings.json` and require no manual activation.

---

## Git workflow

- **Never commit directly to `main`** — always use a feature branch and open a PR.
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`.
- The `pre-commit` hook blocks commits to `main` and to branches whose PR is already merged or closed.
- Always check a PR is still open before pushing additional commits: `gh pr view <branch> --repo <owner>/<repo>`.