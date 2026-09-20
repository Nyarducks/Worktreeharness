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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sand="$(realpath "$(mktemp -d)")"
trap 'rm -rf "${sand}"' EXIT

# run_matrix <tag> <lab-root> <checkout>
# Runs the full hook matrix against one sandboxed checkout. <lab-root> is the
# directory holding repos/+worktree/; <checkout> holds the hook trees.
run_matrix() {
  local tag="$1" lab="$2" co="$3"
  local h_claude="${co}/.claude/hooks"
  local h_agents="${co}/.agents/hooks"
  local h_codex="${co}/.codex/hooks"
  local h_devin="${co}/.devin/hooks"

  # Targets: an in-zone path under worktree/, and paths outside the lab.
  # outside/ext_* live under $HOME — /tmp itself is a default allowlist
  # entry, so a lab-external path must come from elsewhere. None of them
  # need to exist: the guards only resolve and prefix-match.
  local inside="${lab}/worktree/SomeRepo/feat-y/file.txt"
  local outside="${HOME}/wth-outside-${tag}/evil.txt"
  local ext_a="${HOME}/wth-ext-a-${tag}"   # allowed via checkout .env
  local ext_b="${HOME}/wth-ext-b-${tag}"   # allowed via lab-root .env

  # ALLOWED_EXT_DIRS is honored from both the checkout's .env and the lab
  # root's .env (union). In the unified topology both are the same file.
  if [[ "${co}" == "${lab}" ]]; then
    printf 'ALLOWED_EXT_DIRS=%s,%s\n' "${ext_a}" "${ext_b}" > "${co}/.env"
  else
    printf 'ALLOWED_EXT_DIRS=%s\n' "${ext_a}" > "${co}/.env"
    printf 'ALLOWED_EXT_DIRS=%s\n' "${ext_b}" > "${lab}/.env"
  fi

  # ---- claude (.claude/settings.json format) ----
  expect_allow "${tag} claude write: inside worktree"  "${h_claude}/guard-writes-to-worktree.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} claude write: outside lab"      "${h_claude}/guard-writes-to-worktree.sh" "$(pj_file "${outside}" "${co}")"
  expect_allow "${tag} claude write: checkout .env dir" "${h_claude}/guard-writes-to-worktree.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"
  expect_allow "${tag} claude write: lab .env dir"     "${h_claude}/guard-writes-to-worktree.sh" "$(pj_file "${ext_b}/f.txt" "${co}")"

  expect_allow "${tag} claude read: inside root"       "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} claude read: /etc/shadow"       "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "/etc/shadow" "${co}")"
  expect_allow "${tag} claude read: allowlisted"       "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"
  expect_allow "${tag} claude read: agent dir builtin" "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "${HOME}/.codex/config.toml" "${co}")"
  expect_allow "${tag} claude read: /tmp default"      "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "/tmp/wth-scratch-${tag}.txt" "${co}")"

  expect_allow "${tag} claude bash: ls"                "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} claude bash: rm -rf ~"          "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} claude bash: rm -rf /"          "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "rm -rf /" "${co}")"
  expect_deny  "${tag} claude bash: sudo rm -rf /etc"  "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "sudo rm -rf /etc" "${co}")"
  expect_deny  "${tag} claude bash: cat /etc/passwd"   "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} claude bash: allowlisted path"  "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "cat ${ext_b}/f.txt" "${co}")"
  expect_allow "${tag} claude bash: ~ agent dir"       "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "cat ~/.claude/settings.json" "${co}")"
  expect_deny  "${tag} claude bash: ~ outside lab"     "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "cat ~/secret.txt" "${co}")"
  expect_allow "${tag} claude bash: ~ in quoted text"  "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "git commit -m 'mention ~/.claude here'" "${co}")"

  # ---- antigravity (.agents/hooks.json, .toolCall.args format) ----
  expect_allow "${tag} agy write: inside worktree"     "${h_agents}/guard-writes-to-worktree.sh" "$(pj_agy_file "${inside}" "${co}")"
  expect_deny  "${tag} agy write: outside lab"         "${h_agents}/guard-writes-to-worktree.sh" "$(pj_agy_file "${outside}" "${co}")"
  expect_allow "${tag} agy write: lab .env dir"        "${h_agents}/guard-writes-to-worktree.sh" "$(pj_agy_file "${ext_b}/f.txt" "${co}")"

  expect_allow "${tag} agy read: inside root"          "${h_agents}/restrict-to-repo-root.sh" "$(pj_agy_file "${inside}" "${co}")"
  expect_deny  "${tag} agy read: /etc/shadow"          "${h_agents}/restrict-to-repo-root.sh" "$(pj_agy_file "/etc/shadow" "${co}")"

  expect_allow "${tag} agy bash: ls"                   "${h_agents}/guard-bash-commands.sh" "$(pj_agy_cmd "ls -la" "${co}")"
  expect_deny  "${tag} agy bash: rm -rf ~"             "${h_agents}/guard-bash-commands.sh" "$(pj_agy_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} agy bash: cat /etc/passwd"      "${h_agents}/guard-bash-commands.sh" "$(pj_agy_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} agy bash: allowlisted path"     "${h_agents}/guard-bash-commands.sh" "$(pj_agy_cmd "cat ${ext_a}/f.txt" "${co}")"

  # ---- codex (.codex/hooks.json: Bash + apply_patch matchers) ----
  expect_allow "${tag} codex patch: inside worktree"   "${h_codex}/guard-writes-to-worktree.sh" "$(pj_patch "${inside}" "${co}")"
  expect_deny  "${tag} codex patch: outside lab"       "${h_codex}/guard-writes-to-worktree.sh" "$(pj_patch "${outside}" "${co}")"
  expect_allow "${tag} codex patch: allowlisted"       "${h_codex}/guard-writes-to-worktree.sh" "$(pj_patch "${ext_a}/f.txt" "${co}")"

  expect_allow "${tag} codex bash: ls"                 "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} codex bash: rm -rf ~"           "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} codex bash: cat /etc/passwd"    "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} codex bash: allowlisted path"   "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "cat ${ext_b}/f.txt" "${co}")"
  expect_allow "${tag} codex bash: agent dir builtin"  "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "cat ${HOME}/.gemini/settings.json" "${co}")"
  expect_allow "${tag} codex bash: /tmp default"       "${h_codex}/guard-bash-commands.sh" "$(pj_cmd "cat /tmp/wth-scratch-${tag}.txt" "${co}")"

  # ---- devin (.devin/hooks.v1.json format) ----
  expect_allow "${tag} devin write: inside worktree"   "${h_devin}/guard-writes-to-worktree.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} devin write: outside lab"       "${h_devin}/guard-writes-to-worktree.sh" "$(pj_file "${outside}" "${co}")"
  expect_allow "${tag} devin write: checkout .env dir" "${h_devin}/guard-writes-to-worktree.sh" "$(pj_file "${ext_a}/f.txt" "${co}")"
  expect_allow "${tag} devin write: agent dir builtin" "${h_devin}/guard-writes-to-worktree.sh" "$(pj_file "${HOME}/.claude/settings.json" "${co}")"

  expect_allow "${tag} devin read: inside root"        "${h_devin}/restrict-to-repo-root.sh" "$(pj_file "${inside}" "${co}")"
  expect_deny  "${tag} devin read: /etc/shadow"        "${h_devin}/restrict-to-repo-root.sh" "$(pj_file "/etc/shadow" "${co}")"

  expect_allow "${tag} devin bash: ls"                 "${h_devin}/guard-bash-commands.sh" "$(pj_cmd "ls -la" "${co}")"
  expect_deny  "${tag} devin bash: rm -rf ~"           "${h_devin}/guard-bash-commands.sh" "$(pj_cmd "rm -rf ~" "${co}")"
  expect_deny  "${tag} devin bash: rm -rf /"           "${h_devin}/guard-bash-commands.sh" "$(pj_cmd "rm -rf /" "${co}")"
  expect_deny  "${tag} devin bash: cat /etc/passwd"    "${h_devin}/guard-bash-commands.sh" "$(pj_cmd "cat /etc/passwd" "${co}")"
  expect_allow "${tag} devin bash: allowlisted path"   "${h_devin}/guard-bash-commands.sh" "$(pj_cmd "cat ${ext_a}/f.txt" "${co}")"

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
lab="${sand}/split-lab"
build_split "${lab}"
run_matrix "split" "${lab}" "${lab}/worktree/TestRepo/feat-x"

echo "== topology: unified (checkout IS the lab root) =="
lab="${sand}/uni-lab"
build_unified "${lab}"
run_matrix "uni" "${lab}" "${lab}"

echo "== no .env — built-in defaults still apply =="
lab="${sand}/noenv-lab"
build_split "${lab}"
co="${lab}/worktree/TestRepo/feat-x"
h_claude="${co}/.claude/hooks"
expect_allow "noenv claude read: agent dir builtin" "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "${HOME}/.claude/settings.json" "${co}")"
expect_allow "noenv claude read: /tmp default"      "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "/tmp/wth-noenv-x.txt" "${co}")"
expect_deny  "noenv claude read: non-allowlisted"   "${h_claude}/restrict-to-repo-root.sh" "$(pj_file "${HOME}/wth-noenv-x/f.txt" "${co}")"
expect_allow "noenv claude bash: ~ agent dir"       "${h_claude}/guard-bash-commands.sh" "$(pj_cmd "cat ~/.codex/x" "${co}")"

echo
echo "passed: ${pass}  failed: ${fail}"
if [[ ${fail} -gt 0 ]]; then
  printf 'failed tests:\n'
  printf '  - %s\n' "${failed_names[@]}"
  exit 1
fi
