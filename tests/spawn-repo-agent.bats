#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PATH="${REPO_ROOT}/scripts:${PATH}"
  
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}"
  
  HERDR_FAKE_LOG="${BATS_TEST_TMPDIR}/herdr-calls.log"
  : > "${HERDR_FAKE_LOG}"
  export HERDR_FAKE_LOG
  
  # Fake herdr
  cat > "${FAKE_BIN}/herdr" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${HERDR_FAKE_LOG}"
case "$1 $2" in
  "agent send") exit 0 ;;
  "pane send-keys") exit 0 ;;
  "agent wait") exit 0 ;;
  "agent list") echo '{"result":{"agents":[]}}'; exit 0 ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"pane:spawned"}}}'; exit 0 ;;
  "pane run") exit 0 ;;
  *) exit 0 ;;
esac
FAKE
  chmod +x "${FAKE_BIN}/herdr"
  export PATH="${FAKE_BIN}:${PATH}"
  
  export HERDR_ENV=1
  export HERDR_PANE_ID="pane:orchestrator"
  
  # Fake git
  cat > "${FAKE_BIN}/git" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  chmod +x "${FAKE_BIN}/git"



  export WORKTREE_LAB_DIR="${BATS_TEST_TMPDIR}/lab"
  mkdir -p "${WORKTREE_LAB_DIR}/scripts/lib"
  touch "${WORKTREE_LAB_DIR}/scripts/lib/herdr-report.sh"
  touch "${WORKTREE_LAB_DIR}/scripts/lib/worktree-ownership.sh"
  
  cat > "${WORKTREE_LAB_DIR}/scripts/lib/worktree-ownership.sh" <<'FAKE'
worktree_ownership_lookup() { return 1; }
worktree_ownership_claim() { return 0; }
worktree_ownership_release() { return 0; }
worktree_ownership_record_value() { return 0; }
FAKE
  
  mkdir -p "${WORKTREE_LAB_DIR}/worktree/SomeRepo/feat/x"

  cat > "${WORKTREE_LAB_DIR}/scripts/lib/herdr-report.sh" <<'FAKE'
herdr_submit() { return 0; }
FAKE

  cat > "${FAKE_BIN}/create-worktree.sh" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  chmod +x "${FAKE_BIN}/create-worktree.sh"
}

@test "spawn-repo-agent fails if task exceeds 500 characters" {
  local oversized_task
  oversized_task="$(printf 'a%.0s' $(seq 1 501))"
  
  run "${REPO_ROOT}/scripts/spawn-repo-agent.sh" "owner/SomeRepo" "feat/x" -- "${oversized_task}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exceeds the 500-char limit"* ]]
  [[ "$output" == *"Please shorten it"* ]]
  
  # Ensure herdr was never called to send any message
  [ ! -s "${HERDR_FAKE_LOG}" ] || ! grep -q "agent send" "${HERDR_FAKE_LOG}"
}

@test "spawn-repo-agent fails if total envelope exceeds 800 characters" {
  # We use a 400-char task, but mock HERDR_PANE_ID to be extremely long to push total message size > 800
  export HERDR_PANE_ID="$(printf 'a%.0s' $(seq 1 400))"
  local normal_task
  normal_task="$(printf 'a%.0s' $(seq 1 400))"
  
  run "${REPO_ROOT}/scripts/spawn-repo-agent.sh" "owner/SomeRepo" "feat/x" -- "${normal_task}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exceeds the 800-char cap"* ]]
  [[ "$output" == *"Please shorten the task description"* ]]
}

@test "spawn-repo-agent successfully sends a 500-character task with mandatory file reference" {
  local normal_task
  normal_task="$(printf 'a%.0s' $(seq 1 500))"
  
  run "${REPO_ROOT}/scripts/spawn-repo-agent.sh" "owner/SomeRepo" "feat/x" -- "${normal_task}"
  [ "$status" -eq 0 ]
  
  # Ensure herdr was called to send the message
  grep -q "agent send pane:spawned" "${HERDR_FAKE_LOG}"
  # Ensure mandatory file reference is in the sent message
  grep -q "use the Read tool to read" "${HERDR_FAKE_LOG}"
  grep -q "worker-bootstrap.md completely" "${HERDR_FAKE_LOG}"
}

@test "ensure_trusted_workspace recovers from malformed settings.json" {
  export HOME="${BATS_TEST_TMPDIR}/home_malformed"
  mkdir -p "${HOME}/.gemini/antigravity-cli"
  local settings_file="${HOME}/.gemini/antigravity-cli/settings.json"
  
  # Write malformed JSON
  echo "corrupted data {" > "${settings_file}"
  
  run "${REPO_ROOT}/scripts/spawn-repo-agent.sh" "owner/SomeRepo" "feat/x" -- "test task"
  [ "$status" -eq 0 ]
  
  # Verify it created a backup
  local backup_exists=0
  for f in "${settings_file}.corrupt-"*.bak; do
    if [ -f "$f" ]; then
      backup_exists=1
      break
    fi
  done
  [ "$backup_exists" -eq 1 ]
  
  # Verify the original file was reset and updated correctly
  run jq -r '.trustedWorkspaces[]' "${settings_file}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/worktree/SomeRepo/feat/x"* ]]
}

@test "ensure_trusted_workspace serializes concurrent updates and recovery" {
  export HOME="${BATS_TEST_TMPDIR}/home_concurrent"
  mkdir -p "${HOME}/.gemini/antigravity-cli"
  local settings_file="${HOME}/.gemini/antigravity-cli/settings.json"
  # Start with malformed JSON to test concurrent recovery
  echo "corrupted data {" > "${settings_file}"
  
  # Run 10 instances concurrently
  for i in {1..10}; do
    mkdir -p "${WORKTREE_LAB_DIR}/worktree/SomeRepo/feat/branch${i}"
    "${REPO_ROOT}/scripts/spawn-repo-agent.sh" "owner/SomeRepo" "feat/branch${i}" -- "test task" >/dev/null 2>&1 &
  done
  wait
  
  # Verify all 10 were written without data loss
  local count
  count="$(jq '.trustedWorkspaces | length' "${settings_file}")"
  if [ "$count" -ne 10 ]; then
    echo "Count was $count, expected 10. File content:" >&3
    cat "${settings_file}" >&3
  fi
  [ "$count" -eq 10 ]
}
