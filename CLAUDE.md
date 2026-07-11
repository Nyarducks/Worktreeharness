# CLAUDE.md — Worktreeharness

A framework for worktree-driven multi-repository development. Manages base clones under `repos/` and active worktrees under `worktree/`. Supports developing this harness itself and any external GitHub repository.

> **ABSOLUTE RULE — NO EXCEPTIONS**: Before touching ANY file, invoke `/parallel-worktree`. All code changes must happen inside a worktree under `worktree/`. The guard hook enforces this — writes outside `worktree/` are blocked. Do not attempt to bypass it.

> **Never edit `repos/` directly**: `repos/` holds bare base clones. Always create a worktree via `scripts/create-worktree.sh <owner>/<repo> <branch>` before making any changes.

> **Never use `cd` to navigate into repositories**: Use `git -C <path>` for git commands and absolute paths for all file operations. `cd` causes CWD drift which breaks relative-path hooks.

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

### This harness itself (nyarducks/Worktreeharness)

```bash
scripts/create-worktree.sh nyarducks/Worktreeharness feat/improve-scripts
# → worktree/Worktreeharness/feat/improve-scripts/
```

---

## Git Workflow

- Never commit directly to `main` — always use a feature branch + PR
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`
- The pre-commit hook blocks direct commits to `main` and commits to already-merged/closed PR branches

---

## Skills

| Skill | When to use |
|---|---|
| `/parallel-worktree` | Before any code change — sets up or resumes a worktree |
| `/git-operations` | Branching, committing, PR creation/editing |
| `/pr-review-fix` | Reviewing a PR and auto-fixing findings |
| `/setup-harness` | Bootstrapping this framework in a new repo, or adding a new repo to develop |
