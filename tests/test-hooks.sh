#!/usr/bin/env bash
# test-hooks.sh — stdin-JSON simulation of every agent PreToolUse hook.
#
# Reproduces the JSON each agent CLI sends on stdin and asserts the hook's
# allow/deny decision, without launching a real agent. Covers both supported
# lab topologies:
#   split    <lab>/{repos,worktree}/ + checkout under worktree/<repo>/<branch>
#   unified  the checkout IS the lab root (legacy layout)
#
# Usage: bash tests/test-hooks.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SAND="$(realpath "$(mktemp -d)")"
trap 'rm -rf "${SAND}"' EXIT

# run_matrix <tag> <lab-root> <checkout>
# Runs the full hook matrix against one sandboxed checkout. <lab-root> is the
# directory holding repos/+worktree/; <checkout> holds the hook trees.
run_matrix() {
  local tag="$1" lab="$2" co="$3"
  local H_CLAUDE="${co}/.claude/hooks"
  local H_AGENTS="${co}/.agents/hooks"
  local H_CODEX="${co}/.codex/hooks"
  local H_DEVIN="${co}/.devin/hooks"

  # Targets: an in-zone path under worktree/, and paths outside the lab.
  local inside="${lab}/worktree/SomeRepo/feat-y/file.txt"
  local outside="${SAND}/outside-${tag}/evil.txt"
  local ext_a="${SAND}/ext-a-${tag}"   # allowed via checkout .env
  local ext_b="${SAND}/ext-b-${tag}"   # allowed via lab-root .env
  mkdir -p "${SAND}/outside-${tag}" "${ext_a}" "${ext_b}"

  # ALLOWED_EXT_DIRS is honored from both the checkout's .env and the lab
  # root's .env (union). In the unified topology both are the same file.
  if [[ "${co}" == "${lab}" ]]; then
    printf 'ALLOWED_EXT_DIRS=%s,%s\n' "${ext_a}" "${ext_b}" > "${co}/.env"
  else
    printf 'ALLOWED_EXT_DIRS=%s\n' "${ext_a}" > "${co}/.env"
    printf 'ALLOWED_EXT_DIRS=%s\n' "${ext_b}" > "${lab}/.env"
  fi

  # ---- claude (.claude/settings.json format) ----
  expect_allow "${tag} claude write: inside worktree"  "${H_CLAUDE}/guard-writes-to-worktree.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} claude write: outside lab"      "${H_CLAUDE}/guard-writes-to-worktree.sh" "$(pj_file "${outside}" "${co}")"
  expect_allow "${tag} claude write: checkout .env dir" "${H_CLAUDE}/guard-writes-to-worktree.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"
  expect_allow "${tag} claude write: lab .env dir"     "${H_CLAUDE}/guard-writes-to-worktree.sh" "$(pj_file "${ext_b}/f.txt" "${co}")"

  expect_allow "${tag} claude read: inside root"       "${H_CLAUDE}/restrict-to-repo-root.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} claude read: /etc/shadow"       "${H_CLAUDE}/restrict-to-repo-root.sh" "$(pj_file "/etc/shadow" "${co}")"
  expect_allow "${tag} claude read: allowlisted"       "${H_CLAUDE}/restrict-to-repo-root.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"

  expect_allow "${tag} claude bash: ls"                "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} claude bash: rm -rf ~"          "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} claude bash: rm -rf /"          "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "rm -rf /" "${co}")"
  expect_deny  "${tag} claude bash: sudo rm -rf /etc"  "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "sudo rm -rf /etc" "${co}")"
  expect_deny  "${tag} claude bash: cat /etc/passwd"   "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} claude bash: allowlisted path"  "${H_CLAUDE}/guard-bash-commands.sh" "$(pj_cmd "cat ${ext_b}/f.txt" "${co}")"

  # ---- antigravity (.agents/hooks.json, .toolCall.args format) ----
  expect_allow "${tag} agy write: inside worktree"     "${H_AGENTS}/guard-writes-to-worktree.sh" "$(pj_agy_file "${inside}" "${co}")"
  expect_deny  "${tag} agy write: outside lab"         "${H_AGENTS}/guard-writes-to-worktree.sh" "$(pj_agy_file "${outside}" "${co}")"
  expect_allow "${tag} agy write: lab .env dir"        "${H_AGENTS}/guard-writes-to-worktree.sh" "$(pj_agy_file "${ext_b}/f.txt" "${co}")"

  expect_allow "${tag} agy read: inside root"          "${H_AGENTS}/restrict-to-repo-root.sh" "$(pj_agy_file "${inside}" "${co}")"
  expect_deny  "${tag} agy read: /etc/shadow"          "${H_AGENTS}/restrict-to-repo-root.sh" "$(pj_agy_file "/etc/shadow" "${co}")"

  expect_allow "${tag} agy bash: ls"                   "${H_AGENTS}/guard-bash-commands.sh" "$(pj_agy_cmd "ls -la" "${co}")"
  expect_deny  "${tag} agy bash: rm -rf ~"             "${H_AGENTS}/guard-bash-commands.sh" "$(pj_agy_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} agy bash: cat /etc/passwd"      "${H_AGENTS}/guard-bash-commands.sh" "$(pj_agy_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} agy bash: allowlisted path"     "${H_AGENTS}/guard-bash-commands.sh" "$(pj_agy_cmd "cat ${ext_a}/f.txt" "${co}")"

  # ---- codex (.codex/hooks.json: Bash + apply_patch matchers) ----
  expect_allow "${tag} codex patch: inside worktree"   "${H_CODEX}/guard-writes-to-worktree.sh" "$(pj_patch "${inside}" "${co}")"
  expect_deny  "${tag} codex patch: outside lab"       "${H_CODEX}/guard-writes-to-worktree.sh" "$(pj_patch "${outside}" "${co}")"
  expect_allow "${tag} codex patch: allowlisted"       "${H_CODEX}/guard-writes-to-worktree.sh" "$(pj_patch "${ext_a}/f.txt" "${co}")"

  expect_allow "${tag} codex bash: ls"                 "${H_CODEX}/restrict-to-harness-root.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} codex bash: rm -rf ~"           "${H_CODEX}/restrict-to-harness-root.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} codex bash: cat /etc/passwd"    "${H_CODEX}/restrict-to-harness-root.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} codex bash: allowlisted path"   "${H_CODEX}/restrict-to-harness-root.sh" "$(pj_cmd "cat ${ext_b}/f.txt" "${co}")"

  # ---- devin (.devin/hooks.v1.json format) ----
  expect_allow "${tag} devin write: inside worktree"   "${H_DEVIN}/guard-writes-to-worktree.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} devin write: outside lab"       "${H_DEVIN}/guard-writes-to-worktree.sh" "$(pj_file "${outside}" "${co}")"
  expect_allow "${tag} devin write: checkout .env dir" "${H_DEVIN}/guard-writes-to-worktree.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"

  expect_allow "${tag} devin read: inside root"        "${H_DEVIN}/restrict-to-repo-root.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} devin read: /etc/shadow"        "${H_DEVIN}/restrict-to-repo-root.sh" "$(pj_file "/etc/shadow" "${co}")"

  expect_allow "${tag} devin bash: ls"                 "${H_DEVIN}/guard-bash-commands.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} devin bash: rm -rf ~"           "${H_DEVIN}/guard-bash-commands.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} devin bash: rm -rf /"           "${H_DEVIN}/guard-bash-commands.sh" "$(pj_cmd "rm -rf /" "${co}")"
  expect_deny  "${tag} devin bash: cat /etc/passwd"    "${H_DEVIN}/guard-bash-commands.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} devin bash: allowlisted path"   "${H_DEVIN}/guard-bash-commands.sh" "$(pj_cmd "cat ${ext_a}/f.txt" "${co}")"

  # ---- config command resolution ----
  # Regression: hook commands must resolve to a real script from the checkout
  # cwd (git rev-parse --show-toplevel). Run each configured command verbatim
  # with a payload its hook must deny — a silently-missing path fails here.
  local cfg cmd payload out rc
  for cfg in "${co}/.claude/settings.json" "${co}/.agents/hooks.json" \
             "${co}/.codex/hooks.json" "${co}/.devin/hooks.v1.json"; do
    while IFS= read -r cmd; do
      [[ -z "${cmd}" ]] && continue
      case "${cmd}" in
        *.agents/*guard-bash*)    payload="$(pj_agy_cmd "rm -rf ~" "${co}")" ;;
        *.agents/*)               payload="$(pj_agy_file "${outside}" "${co}")" ;;
        *.codex/*guard-writes*)   payload="$(pj_patch "${outside}" "${co}")" ;;
        *.codex/*)                payload="$(pj_cmd "rm -rf ~" "${co}")" ;;
        *guard-bash*)             payload="$(pj_cmd "rm -rf ~" "${co}")" ;;
        *)                        payload="$(pj_file "${outside}" "${co}")" ;;
      esac
      out="$(cd "${co}" && printf '%s' "${payload}" | eval "${cmd}" 2>&1)"; rc=$?
      if [[ ${rc} -eq 0 ]] && is_deny_json "${out}"; then
        ok "${tag} config: ${cmd##*/} resolves and fires"
      else
        bad "${tag} config: ${cmd##*/} resolves and fires"
        printf '       rc=%s out=%s\n' "${rc}" "${out:0:200}"
      fi
    done < <(jq -r '.. | objects | .command? // empty' "${cfg}")
  done
}

echo "== topology: split (checkout under <lab>/worktree/<repo>/<branch>) =="
LAB="${SAND}/split-lab"
build_split "${LAB}"
run_matrix "split" "${LAB}" "${LAB}/worktree/TestRepo/feat-x"

echo "== topology: unified (checkout IS the lab root) =="
LAB="${SAND}/uni-lab"
build_unified "${LAB}"
run_matrix "uni" "${LAB}" "${LAB}"

echo
echo "passed: ${PASS}  failed: ${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf 'failed tests:\n'
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
