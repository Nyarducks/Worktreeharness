#!/usr/bin/env bash
# Shared helpers for tests/test-hooks.sh.
#
# Simulates agent-CLI PreToolUse hook invocations: each agent feeds its hook
# command a JSON payload on stdin and interprets the result as
#   allow  -> exit 0, no output
#   deny   -> exit 0, JSON decision on stdout
# The hook output shape differs per agent, so deny detection accepts
#   {hookSpecificOutput:{permissionDecision:"deny"}}   (claude, codex)
#   {decision:"deny"|"block"}                          (antigravity, devin)
#
# shellcheck disable=SC2154
# (repo_root is provided by the sourcing test script)

pass=0
fail=0
declare -a failed_names=()

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); failed_names+=("$1"); printf '  fail %s\n' "$1"; }

# run_hook <script> <json> — feed payload on stdin, capture stdout+stderr.
run_hook() {
  printf '%s' "$2" | bash "$1" 2>&1
}

is_deny_json() {
  jq -e '(.hookSpecificOutput.permissionDecision // .decision) as $d
         | ($d == "deny" or $d == "block")' >/dev/null 2>&1 <<<"$1"
}

# expect_allow <name> <script> <json>
expect_allow() {
  local out rc
  out="$(run_hook "$2" "$3")"; rc=$?
  if [[ ${rc} -eq 0 && -z "${out}" ]]; then
    ok "$1"
  else
    bad "$1"
    printf '       rc=%s out=%s\n' "${rc}" "${out:0:300}"
  fi
}

# expect_deny <name> <script> <json>
expect_deny() {
  local out rc
  out="$(run_hook "$2" "$3")"; rc=$?
  if [[ ${rc} -eq 0 ]] && is_deny_json "${out}"; then
    ok "$1"
  else
    bad "$1"
    printf '       rc=%s out=%s\n' "${rc}" "${out:0:300}"
  fi
}

# --- stdin payload builders -------------------------------------------------

# claude / devin / codex format: .tool_input.{file_path,command}, .cwd
pj_file() { jq -nc --arg p "$1" --arg c "${2:-}" '{tool_input:{file_path:$p},cwd:$c}'; }
pj_cmd()  { jq -nc --arg p "$1" --arg c "${2:-}" '{tool_input:{command:$p},cwd:$c}'; }

# codex apply_patch arrives as a patch document inside .tool_input.command
pj_patch() {
  jq -nc --arg p "$1" --arg c "${2:-}" \
    '{tool_input:{command:("*** Begin Patch\n*** Add File: " + $p + "\n+x\n*** End Patch")},cwd:$c}'
}

# antigravity format: .toolCall.args.{TargetFile,AbsolutePath,CommandLine,Cwd}
pj_agy_file() { jq -nc --arg p "$1" --arg c "${2:-}" '{toolCall:{args:{TargetFile:$p,Cwd:$c}}}'; }
pj_agy_cmd()  { jq -nc --arg p "$1" --arg c "${2:-}" '{toolCall:{args:{CommandLine:$p,Cwd:$c}}}'; }

# --- sandbox builders --------------------------------------------------------

# install_hooks <checkout> — copy hook trees, hook configs, and scripts/lib
# into a test checkout so the sandbox mirrors a real repo checkout.
install_hooks() {
  local co="$1" d
  for d in .claude .agents .codex .devin; do
    mkdir -p "${co}/${d}"
    cp -R "${repo_root}/${d}/hooks" "${co}/${d}/"
  done
  cp "${repo_root}/.claude/settings.json"   "${co}/.claude/"
  cp "${repo_root}/.agents/hooks.json"      "${co}/.agents/"
  cp "${repo_root}/.codex/hooks.json"       "${co}/.codex/"
  cp "${repo_root}/.devin/hooks.v1.json"    "${co}/.devin/"
  mkdir -p "${co}/scripts"
  cp -R "${repo_root}/scripts/lib" "${co}/scripts/"
  cp "${repo_root}/.env.sample" "${co}/"   # ships the default allowlist
}

# build_split <lab> — <lab>/{repos,worktree}/ with a real linked-worktree
# checkout at worktree/TestRepo/feat-x (mirrors the production topology).
# A real git worktree is required: `git rev-parse --show-toplevel` must
# resolve for the hook-command resolution tests, and the hooks find the
# lab root by walking up to the dir holding both repos/ and worktree/.
build_split() {
  local lab="$1"
  mkdir -p "${lab}/repos" "${lab}/worktree"
  git -C "${lab}/repos" init -q TestRepo
  git -C "${lab}/repos/TestRepo" -c user.email=test@example.com -c user.name=test \
    commit -qm init --allow-empty
  git -C "${lab}/repos/TestRepo" worktree add -q "${lab}/worktree/TestRepo/feat-x" -b feat-x
  install_hooks "${lab}/worktree/TestRepo/feat-x"
}

# build_unified <dir> — the checkout IS the lab root (legacy topology:
# repos/, worktree/, hooks, and scripts/ all inside one checkout).
build_unified() {
  local lab="$1"
  mkdir -p "${lab}/repos" "${lab}/worktree"
  git -C "${lab}" init -q
  git -C "${lab}" -c user.email=test@example.com -c user.name=test \
    commit -qm init --allow-empty
  install_hooks "${lab}"
}
