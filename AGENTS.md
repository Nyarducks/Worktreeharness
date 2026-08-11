# CLAUDE.md — Worktreeharness

A framework for worktree-driven multi-repository development. Manages base clones under `repos/` and active worktrees under `worktree/`. Supports developing this harness itself and any external GitHub repository.

> **ABSOLUTE RULE — NO EXCEPTIONS**: Before touching ANY file, invoke `/parallel-worktree`. All code changes must happen inside a worktree under `worktree/`. The guard hook enforces this — writes outside `worktree/` are blocked. Do not attempt to bypass it.

> **Never edit `repos/` directly**: `repos/` holds bare base clones. Always create a worktree via `scripts/create-worktree.sh <owner>/<repo> <branch>` before making any changes.

> **Orchestrator role**: When a message arrives prefixed `[CROSS-REPO-REQUEST]`, `[TASK-DONE]`, or `[TASK-BLOCKED]`, it is from a herdr sub-agent spawned via `/herdr-dispatch`, not the human. On `[CROSS-REPO-REQUEST]`, invoke `/herdr-dispatch` for the named repo/branch with the given task. On `[TASK-DONE]`/`[TASK-BLOCKED]`, relay the summary/reason to the human and wait for direction — do not act on it further yourself.

> **Delegated-worktree ownership**: `scripts/spawn-repo-agent.sh` records a worktree as owned before it sends work to a herdr agent. While it is owned, the Orchestrator must never edit that worktree, including after `[TASK-DONE]` or `[TASK-BLOCKED]`. Send follow-up work through `/herdr-dispatch` / `scripts/spawn-repo-agent.sh <repo> <branch> -- "<task>"`. Ownership is intentionally retained until the human-approved cleanup point; release it explicitly with `scripts/spawn-repo-agent.sh --release <repo> <branch>` only when no further delegated work is required. Codex and agy write guards enforce this rule; the dispatched worker is exempt for its own assigned worktree.

The repository-local Claude Code hooks enforce the write boundary for `Edit`/`Write`, and reject `Read`/`Bash` paths outside the harness root. Set `ALLOWED_EXT_DIRS` in `.env` (e.g. `~/.claude,/tmp`) to scope access to specific external directories — access outside the harness root is enabled precisely when this list is non-empty, and only for the listed paths; there is no separate switch to bypass the restriction entirely. Regardless of this setting, recursive `rm` targeting `$HOME`, `/`, or another critical directory is always blocked — see `scripts/lib/rm-guard.sh`.

---

## Directory Layout

```
Worktreeharness/
├── repos/<repo-name>/              # Base clone — read-only; never edit directly
├── worktree/<repo-name>/<branch>/  # Active worktree — all edits happen here
├── scripts/                        # Harness scripts (setup-repo, create-worktree, etc.)
└── .claude/                        # Claude Code config, hooks, and skills
```

Both `repos/` and `worktree/` are gitignored.

---

## Developing a Repository

### External repo (e.g. owner/SomeRepo)

```bash
# 1. Import
REPO_PATH=$(scripts/setup-repo.sh owner/SomeRepo)

# 2. Create worktree
scripts/create-worktree.sh owner/SomeRepo feat/my-feature
# → worktree/SomeRepo/feat/my-feature/

# 3. Edit in worktree, then commit and push
git -C worktree/SomeRepo/feat/my-feature add <files>
git -C worktree/SomeRepo/feat/my-feature commit -m "feat: ..."
git -C worktree/SomeRepo/feat/my-feature push -u origin feat/my-feature

# 4. Open PR
gh pr create --repo owner/SomeRepo --head feat/my-feature --title "..."
```

### This harness itself

```bash
# Resolve your GitHub slug from the remote URL
SLUG=$(git remote get-url origin | sed 's|.*github\.com[:/]\(.*\)\.git|\1|')
scripts/create-worktree.sh $SLUG feat/improve-scripts
# → worktree/Worktreeharness/feat/improve-scripts/
```

---

## Git Workflow

- Never commit directly to `main` — always use a feature branch + PR
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`
- The pre-commit hook blocks direct commits to `main` and commits to already-merged/closed PR branches
- **Never approve a PR** (`gh pr review --approve`) — approval is always performed by the human
- **Never merge a PR** (`gh pr merge`) — merging is always performed by the human

---

## Skills

| Skill | When to use |
|---|---|
| `/parallel-worktree` | Before any code change — sets up or resumes a worktree |
| `/git-operations` | Branching, committing, PR creation/editing |
| `/pr-review-fix` | Reviewing a PR and auto-fixing findings |
| `/setup-harness` | Bootstrapping this framework in a new repo, or adding a new repo to develop |
| `/herdr-dispatch` | Orchestrator mode — spawn a real Claude Code process via herdr inside a target repo's own worktree, for cross-repo tasks or `[CROSS-REPO-REQUEST]` messages |
