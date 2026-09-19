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
mkdir -p .agents/skills/git-operations .agents/skills/parallel-worktree \
          .agents/skills/pr-review-fix .agents/skills/setup-harness \
          .claude/hooks .codex/hooks .agents/hooks .devin/hooks \
          scripts/hooks scripts/lib repos worktree
```

### 1-2. Copy scripts from the harness

```bash
HARNESS=$(git rev-parse --show-toplevel)   # run from inside Worktreeharness
TARGET=/path/to/new-repo

cp $HARNESS/scripts/setup-repo.sh       $TARGET/scripts/
cp $HARNESS/scripts/create-worktree.sh  $TARGET/scripts/
cp $HARNESS/scripts/setup-hooks.sh      $TARGET/scripts/
cp $HARNESS/scripts/lib/rm-guard.sh     $TARGET/scripts/lib/
cp $HARNESS/scripts/hooks/pre-commit    $TARGET/scripts/hooks/
chmod +x $TARGET/scripts/*.sh $TARGET/scripts/lib/*.sh $TARGET/scripts/hooks/pre-commit
```

### 1-3. Copy skills and per-agent hook scripts

`.agents/skills` is the canonical skills directory — Codex, Devin, and
Antigravity read it natively. `.claude/skills` is a symlink to it.

```bash
cp $HARNESS/.agents/skills/git-operations/SKILL.md    $TARGET/.agents/skills/git-operations/
cp $HARNESS/.agents/skills/parallel-worktree/SKILL.md $TARGET/.agents/skills/parallel-worktree/
cp $HARNESS/.agents/skills/pr-review-fix/SKILL.md     $TARGET/.agents/skills/pr-review-fix/
cp $HARNESS/.agents/skills/setup-harness/SKILL.md     $TARGET/.agents/skills/setup-harness/
ln -s ../.agents/skills $TARGET/.claude/skills

cp $HARNESS/.claude/hooks/*.sh $TARGET/.claude/hooks/
cp $HARNESS/.codex/hooks/*.sh  $TARGET/.codex/hooks/
cp $HARNESS/.agents/hooks/*.sh $TARGET/.agents/hooks/
cp $HARNESS/.devin/hooks/*.sh  $TARGET/.devin/hooks/
chmod +x $TARGET/.claude/hooks/*.sh $TARGET/.codex/hooks/*.sh \
         $TARGET/.agents/hooks/*.sh $TARGET/.devin/hooks/*.sh
```

### 1-4. Verify no absolute paths

The copied skill files use `$(git rev-parse --show-toplevel)` for dynamic path resolution and contain no hardcoded absolute paths. No substitution is needed.

### 1-5. Create per-agent hook configs

Each agent reads its own file — they do not conflict:

- `.claude/settings.json` — Claude Code (`"hooks"` key; Claude has no standalone hooks.json)
- `.codex/hooks.json` — Codex (`"hooks"` key)
- `.agents/hooks.json` — Antigravity (named hook groups at the top level)
- `.devin/hooks.v1.json` — Devin CLI (the hooks object is the entire file)

Copy the reference files instead of writing them by hand:

```bash
cp $HARNESS/.claude/settings.json $TARGET/.claude/
cp $HARNESS/.codex/hooks.json     $TARGET/.codex/
cp $HARNESS/.agents/hooks.json    $TARGET/.agents/
cp $HARNESS/.devin/hooks.v1.json  $TARGET/.devin/
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
.env
```

### 1-8. Create AGENTS.md and CLAUDE.md

`AGENTS.md` is the canonical rules file — write the project's rules there. At minimum include:

```markdown
> **ABSOLUTE RULE**: Before editing ANY file, invoke `/parallel-worktree`.
> All code changes must happen inside a worktree under `worktree/`.
> Never edit `repos/` directly.
> Never use `cd` to navigate into repositories — use `git -C <path>`.
```

`CLAUDE.md` is a one-line pointer so Claude Code reads the same rules:

```
@AGENTS.md
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

Read and edit files using absolute paths resolved from the harness root:

```bash
LAB=$(git rev-parse --show-toplevel)

# Read
cat $LAB/worktree/<repo>/feat/<topic>/src/file.ts

# Edit via Claude Code tool — pass the full path printed by create-worktree.sh
# Edit: $LAB/worktree/<repo>/feat/<topic>/src/file.ts
```

### 2-4. Commit and push

```bash
git -C worktree/<repo>/feat/<topic> add <files>
git -C worktree/<repo>/feat/<topic> commit -m "feat(<scope>): ..."
git -C worktree/<repo>/feat/<topic> push -u origin feat/<topic>
```

### 2-5. Create a PR against the original repo

**PR title, body, and all Decision Log entries must be written in English.**

```bash
PR_URL=$(gh pr create \
  --repo <owner>/<repo> \
  --head feat/<topic> \
  --title "..." \
  --assignee @me \
  --label "<labels>" \
  --body "$(cat <<'EOF'
## Summary

- change 1
- change 2

## Background

Motivation and context

## Test plan

- [ ] item 1
- [ ] item 2

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)")
PR=$(basename "$PR_URL")
```

Immediately after PR creation, log the initial commit to Decision Logs:

```bash
scripts/append-pr-log.sh <owner>/<repo> "$PR" worktree/<repo>/feat/<topic> <<'EOF'
### What changed
- <describe what this commit implements>

### Why
<rationale for the approach taken>
EOF
```

For each subsequent commit pushed to the PR branch, append another entry:

```bash
scripts/append-pr-log.sh <owner>/<repo> "$PR" worktree/<repo>/feat/<topic> <<'EOF'
### What changed
- <describe changes in this commit>

### Why
<reason: review feedback / bug found / design refinement / etc.>
EOF
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
export WORKTREE_LAB_DIR=$(git rev-parse --show-toplevel)
```
