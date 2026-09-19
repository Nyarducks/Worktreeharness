# Contributing

Development rules for Worktreeharness. The non-negotiables live in
`AGENTS.md`; this file covers how to work.

## Worktree workflow

All changes happen in a worktree under `worktree/` — create one before
editing:

```bash
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
```

Base clones under `repos/` are never edited. See
`docs/design/README.md` for the layout.

## Git workflow

- Feature branch + PR; never commit to `main`
- Branch naming: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`
- The pre-commit hook blocks `main` and already-merged/closed PR branches
- Humans approve and merge PRs — agents never do

## Shell script style

Applies to everything under `scripts/` and the hook scripts.

### Safety header

Always start scripts with a standard bash shebang and strict execution
flags to fail fast on errors:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `-e`: exit immediately if a command exits with a non-zero status.
- `-u`: treat unset variables as an error and exit immediately.
- `-o pipefail`: return the exit status of the last command in the
  pipeline that failed.

### Variable naming

- **Constants and environment variables**: UPPERCASE snake_case; mark
  read-only constants explicitly.

  ```bash
  readonly DEFAULT_PORT=8080
  export API_ENDPOINT="https://api.example.com"
  ```

- **Internal and local variables**: lowercase snake_case — avoids
  collisions with environment variables (`PATH`, `USER`, `HOME`).

  ```bash
  local file_name="$1"
  user_count=0
  ```

### Expansion and quoting

- Always wrap variable references in double quotes to prevent word
  splitting and globbing:

  ```bash
  rm -- "$target_file"   # not: rm -- $target_file
  ```

- `${var}` braces are optional for simple references, mandatory for
  concatenation (`"${base}_backup.tar.gz"`), array indexing
  (`"${arr[0]}"`), and parameter expansion (`"${timeout:-30}"`).

### Functions and scope

- Define functions without the `function` keyword:
  `function_name() { ... }`.
- Declare internal variables inside functions with `local`.

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly LOG_DIR="/var/log/app"
readonly MAX_RETRIES=3

backup_logs() {
  local target_app="$1"
  local destination_archive="${LOG_DIR}/${target_app}_archive.tar.gz"

  echo "Creating archive: ${destination_archive}"
}

backup_logs "service-a"
```

## Tests

Shell tests live in `tests/`. Run them before pushing:

```bash
bash tests/test-hooks.sh                    # guard-hook allow/deny matrix
bash tests/test-sandbox.sh                  # bwrap sandbox confinement
for t in tests/scripts/test-*.sh; do bash "$t"; done   # per-script tests
```

Hook changes must extend `test-hooks.sh` (it simulates each agent's stdin
JSON protocol). Sandbox changes must extend `test-sandbox.sh`. Any change
to `scripts/*.sh` must extend the matching `tests/scripts/test-*.sh` —
stubs for `gh`/`herdr`/`bwrap` live in `tests/scripts/lib.sh`. CI
(`.github/workflows/ci.yaml`) runs all suites on PRs that touch `*.sh`.

## Documentation

Docs are part of every change:

- **`docs/design/`** — design docs in Google OKF v0.2 (markdown + YAML
  frontmatter; `type`, `title`, `description`, `status`,
  `last_modified`, `sources`). Design docs capture intent and invariants
  (What/Why/How at the design level), not implementation detail. Update
  the relevant doc in the same commit as any behavior change.
- **`docs/reference/`** — fact inventories (config tables, script/skill
  lists). Same frontmatter convention with `type: Reference`.
- **`docs/adr/`** — record significant decisions as
  `docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences, OKF
  frontmatter `type: ADR`). Numbers are sequential.
- **`README.md`** — quick start only; keep it slim.
- **`AGENTS.md`** — must-follow rules only; do not document structure or
  usage there.
