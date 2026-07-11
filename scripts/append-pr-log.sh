#!/usr/bin/env bash
# Usage: append-pr-log.sh <owner>/<repo> <pr-number> <worktree-path>
#
# Appends the latest commit on <worktree-path> as a collapsed <details> entry
# under "## Decision Logs" in the PR body. The inner content of the entry
# (what changed / why) is read from stdin.
#
# Example:
#   scripts/append-pr-log.sh owner/repo 42 worktree/MyRepo/feat/topic <<'EOF'
#   ### What changed
#   - Rewrote foo() to handle edge case X
#
#   ### Why
#   Review comment pointed out Y was broken when input is empty.
#   EOF
set -euo pipefail

DECISION_LOGS_HEADER="## Decision Logs"

usage() {
  echo "Usage: $0 <owner>/<repo> <pr-number> <worktree-path>" >&2
  echo "  Inner content is read from stdin." >&2
  exit 1
}

read_stdin_content() {
  local CONTENT
  CONTENT="$(cat)"
  if [[ -z "${CONTENT}" ]]; then
    echo "Error: no content on stdin — provide the details body." >&2
    exit 1
  fi
  printf '%s' "${CONTENT}"
}

get_commit_info() {
  local WORKTREE_PATH="$1"
  COMMIT_MSG="$(git -C "${WORKTREE_PATH}" log -1 --pretty=%s)"
  SHORT_SHA="$(git -C "${WORKTREE_PATH}" rev-parse --short HEAD)"
}

build_entry() {
  local INNER_CONTENT="$1"
  printf '<details>\n<summary>%s (%s)</summary>\n\n%s\n\n---\n\n</details>' \
    "${COMMIT_MSG}" "${SHORT_SHA}" "${INNER_CONTENT}"
}

get_pr_body() {
  local OWNER_REPO="$1"
  local PR="$2"
  gh api "repos/${OWNER_REPO}/pulls/${PR}" --jq '.body // ""'
}

append_to_pr_body() {
  local OWNER_REPO="$1"
  local PR="$2"
  local CURRENT_BODY="$3"
  local NEW_ENTRY="$4"

  local NEW_BODY
  if printf '%s' "${CURRENT_BODY}" | grep -qF "${DECISION_LOGS_HEADER}"; then
    NEW_BODY="${CURRENT_BODY}

${NEW_ENTRY}"
  else
    NEW_BODY="${CURRENT_BODY}

${DECISION_LOGS_HEADER}

${NEW_ENTRY}"
  fi

  gh api "repos/${OWNER_REPO}/pulls/${PR}" -X PATCH \
    -f "body=${NEW_BODY}" \
    --jq '.number | "Updated PR #\(.)"'
}

main() {
  [[ $# -ne 3 ]] && usage

  local OWNER_REPO="$1"
  local PR="$2"
  local WORKTREE_PATH="$3"

  local INNER_CONTENT
  INNER_CONTENT="$(read_stdin_content)"

  local COMMIT_MSG SHORT_SHA
  get_commit_info "${WORKTREE_PATH}"

  local NEW_ENTRY
  NEW_ENTRY="$(build_entry "${INNER_CONTENT}")"

  local CURRENT_BODY
  CURRENT_BODY="$(get_pr_body "${OWNER_REPO}" "${PR}")"

  append_to_pr_body "${OWNER_REPO}" "${PR}" "${CURRENT_BODY}" "${NEW_ENTRY}"
}

main "$@"
