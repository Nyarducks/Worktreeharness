---
name: setup-harness
description: Bootstrap the Worktreeharness framework — either into a new base repository, or prepare an external repository under repos/ for worktree-based development. Use when setting up a fresh project or onboarding a new repository into this harness.
---

# Worktreeharness Setup Guide

Two use cases:

| Scenario | What to do |
|---|---|
| **A** — Install the harness framework into a brand-new repo | Follow Section 1 |
| **B** — Add an existing GitHub repo to develop from this harness | Follow Section 2 |

---

## Section 1: Install harness into a new base repository

Use this when you want to create a brand-new repository that uses the worktree-driven workflow from scratch.

### 1-1. Create the repo and directory structure

```bash
gh repo create <owner>/<new-repo> --private --clone
cd <new-repo>
mkdir -p .claude/hooks .claude/skills/git-operations .claude/skills/parallel-worktree \
          .claude/skills/pr-review-fix .claude/skills/setup-harness \
          scripts/hooks repos worktree
```

### 1-2. Copy scripts from the harness

From the Worktreeharness root (`/home/caramel/LocalProject/Worktreeharness`):

```bash
HARNESS=/home/caramel/LocalProject/Worktreeharness
TARGET=/path/to/new-repo

cp $HARNESS/scripts/setup-repo.sh       $TARGET/scripts/
cp $HARNESS/scripts/create-worktree.sh  $TARGET/scripts/
cp $HARNESS/scripts/setup-hooks.sh      $TARGET/scripts/
cp $HARNESS/scripts/hooks/pre-commit    $TARGET/scripts/hooks/
chmod +x $TARGET/scripts/*.sh $TARGET/scripts/hooks/pre-commit
```

### 1-3. Copy Claude hooks and settings

```bash
cp $HARNESS/.claude/hooks/guard-writes-to-worktree.sh  $TARGET/.claude/hooks/
cp $HARNESS/.claude/hooks/restrict-to-repo-root.sh     $TARGET/.claude/hooks/
chmod +x $TARGET/.claude/hooks/*.sh

cp $HARNESS/.claude/skills/git-operations/SKILL.md    $TARGET/.claude/skills/git-operations/
cp $HARNESS/.claude/skills/parallel-worktree/SKILL.md $TARGET/.claude/skills/parallel-worktree/
cp $HARNESS/.claude/skills/pr-review-fix/SKILL.md     $TARGET/.claude/skills/pr-review-fix/
cp $HARNESS/.claude/skills/setup-harness/SKILL.md     $TARGET/.claude/skills/setup-harness/
```

### 1-4. Update path references

Edit `parallel-worktree/SKILL.md` and `pr-review-fix/SKILL.md` to replace:
```
/home/caramel/LocalProject/Worktreeharness/
```
with the new repo's absolute path.

Update `guard-writes-to-worktree.sh`: change the denial message's skill path to point to the new location if needed.

### 1-5. Create .claude/settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/restrict-to-repo-root.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/guard-writes-to-worktree.sh"
          }
        ]
      }
    ]
  }
}
```

### 1-6. Install git hooks

```bash
bash $TARGET/scripts/setup-hooks.sh
```

### 1-7. Add .gitignore

```
repos/
tmp/
worktree/
```

### 1-8. Create CLAUDE.md

Write a CLAUDE.md with the project's rules. At minimum include:

```markdown
> **ABSOLUTE RULE**: Before editing ANY file, invoke `/parallel-worktree`.
> All code changes must happen inside a worktree under `worktree/`.
> Never edit `repos/` directly.
> Never use `cd` to navigate into repositories — use `git -C <path>`.
```

### 1-9. Commit and push

```bash
git add .
git commit -m "chore: bootstrap worktree harness framework"
git push -u origin main
```

---

## Section 2: Add an external repository for development

Use this when you want to develop an existing GitHub repository from within this harness.

### 2-1. Import the repository into repos/

```bash
REPO_PATH=$(scripts/setup-repo.sh <owner>/<repo>)
# Clones to: repos/<repo>/
echo "Imported: $REPO_PATH"
```

This runs `gh repo clone` on first use, or `git pull --ff-only` on subsequent uses.

### 2-2. Create a worktree for your task

```bash
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
# Creates: worktree/<repo>/feat/<topic>/
```

The worktree is branched from `origin/main` of the imported repo.

### 2-3. Work in the worktree

Read and edit files using absolute paths:

```bash
# Read
cat /home/caramel/LocalProject/Worktreeharness/worktree/<repo>/feat/<topic>/src/file.ts

# Edit via Claude Code tool
Edit: /home/caramel/LocalProject/Worktreeharness/worktree/<repo>/feat/<topic>/src/file.ts
```

### 2-4. Commit and push

```bash
git -C worktree/<repo>/feat/<topic> add <files>
git -C worktree/<repo>/feat/<topic> commit -m "feat(<scope>): ..."
git -C worktree/<repo>/feat/<topic> push -u origin feat/<topic>
```

### 2-5. Create a PR against the original repo

```bash
gh pr create \
  --repo <owner>/<repo> \
  --head feat/<topic> \
  --title "..." \
  --body "..."
```

### 2-6. Cleanup after merge

```bash
git -C repos/<repo> worktree remove ../../worktree/<repo>/feat/<topic>
git -C repos/<repo> branch -d feat/<topic>
```

---

## Environment variable

Set `WORKTREE_LAB_DIR` if auto-detection of the harness root fails:

```bash
export WORKTREE_LAB_DIR=/home/caramel/LocalProject/Worktreeharness
```
