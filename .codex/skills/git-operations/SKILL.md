---
name: git-operations
description: Follow the Worktreeharness GitHub workflow. Use when importing repositories, creating branches or commits, creating or editing pull requests, applying labels, recording decision logs, replying to reviews, or cleaning up merged worktrees.
---

# Git and Pull Requests

Work only in `worktree/<repo>/<branch>`; never commit in `repos/` or directly to `main`. Create feature branches from the latest `main` and name them `feat/<feature>`, `fix/<issue>`, or `refactor/<scope>`.

## Repository and commits

Use `gh repo clone <owner>/<repo>` for private repositories. Prefer the harness commands:

```bash
scripts/setup-repo.sh <owner>/<repo>
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
git -C worktree/<repo>/feat/<topic> add <files>
git -C worktree/<repo>/feat/<topic> commit -m "feat(<scope>): <summary>"
```

## Create a pull request

Push before creating the PR. Write the title, body, and decision logs in English. First check for `.github/pull_request_template.md` and use it when present.

```bash
git -C worktree/<repo>/<branch> push -u origin <branch>
gh label list --repo <owner>/<repo>
gh pr create --repo <owner>/<repo> --head <branch> --title "<title>" \
  --assignee @me --label "<component>,<type>" --body "<body>"
```

Always pass `--assignee @me` and at least one component label plus exactly one type label: `bug`, `enhancement`, `dependencies`, `documentation`, or `ci`.

Immediately after PR creation, and after every later pushed commit, record the commit:

```bash
scripts/append-pr-log.sh <owner>/<repo> <pr-number> worktree/<repo>/<branch> <<'EOF'
### What changed
- <change>

### Why
<rationale>
EOF
```

## PR changes and reviews

Use the REST API when `gh pr edit` is unreliable:

```bash
gh api repos/<owner>/<repo>/pulls/<number> -X PATCH \
  -f title="<title>" -f body="<body>"
```

Reply to review comments through `repos/<owner>/<repo>/pulls/<pr>/comments/<comment>/replies`. Quote comment bodies with single quotes if they include backticks. Never approve or merge a PR; these are human actions.

## Cleanup

After merge, remove the worktree and local branch with `git -C repos/<repo> worktree remove ../../worktree/<repo>/<branch>` and `git -C repos/<repo> branch -d <branch>`.
