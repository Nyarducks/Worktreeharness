#!/usr/bin/env bats
# Tests for scripts/lib/herdr-report.sh's herdr_submit, focused on the
# HERDR_REPORT_MAX_CHARS cap: oversized messages must be refused before any
# `herdr agent send` call, and retries must never manage to deliver them.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}"

  HERDR_FAKE_LOG="${BATS_TEST_TMPDIR}/herdr-calls.log"
  : > "${HERDR_FAKE_LOG}"
  export HERDR_FAKE_LOG
  # 0 = `herdr agent wait` succeeds (pane left idle); 1 = it never does.
  export HERDR_FAKE_WAIT_RESULT="${HERDR_FAKE_WAIT_RESULT:-0}"

  cat > "${FAKE_BIN}/herdr" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${HERDR_FAKE_LOG}"
case "$1 $2" in
  "agent send") exit 0 ;;
  "pane send-keys") exit 0 ;;
  "agent wait") [[ "${HERDR_FAKE_WAIT_RESULT}" == "0" ]] ;;
  *) exit 0 ;;
esac
FAKE
  chmod +x "${FAKE_BIN}/herdr"
  export PATH="${FAKE_BIN}:${PATH}"

  unset HERDR_REPORT_MAX_CHARS
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/lib/herdr-report.sh"
}

@test "herdr_submit sends a message within the default cap" {
  run herdr_submit "pane:1" "short status update"
  [ "$status" -eq 0 ]
  grep -q "agent send pane:1 short status update" "${HERDR_FAKE_LOG}"
}

@test "herdr_submit refuses a message over the default 800-char cap" {
  local oversized
  oversized="$(printf 'a%.0s' $(seq 1 801))"
  run herdr_submit "pane:1" "${oversized}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" == *"801"* ]]
  [[ "$output" == *"800"* ]]
  # No herdr command of any kind was invoked — the send never happened.
  [ ! -s "${HERDR_FAKE_LOG}" ]
}

@test "herdr_submit accepts a message exactly at the cap boundary" {
  local exact
  exact="$(printf 'a%.0s' $(seq 1 800))"
  run herdr_submit "pane:1" "${exact}"
  [ "$status" -eq 0 ]
}

@test "herdr_submit does not retry-send an oversized message" {
  export HERDR_FAKE_WAIT_RESULT=1
  local oversized
  oversized="$(printf 'a%.0s' $(seq 1 900))"
  run herdr_submit "pane:1" "${oversized}"
  [ "$status" -eq 1 ]
  # Even with a failing `agent wait` (which would normally drive retries),
  # an oversized message must never reach `herdr agent send` at all.
  [ ! -s "${HERDR_FAKE_LOG}" ]
}

@test "herdr_submit honors a custom HERDR_REPORT_MAX_CHARS" {
  export HERDR_REPORT_MAX_CHARS=10
  run herdr_submit "pane:1" "this is definitely over ten characters"
  [ "$status" -eq 1 ]
  [[ "$output" == *"10-char cap"* ]]
  [ ! -s "${HERDR_FAKE_LOG}" ]
}

@test "herdr_submit retries the Enter keypress when the pane stays idle, for an allowed-size message" {
  export HERDR_FAKE_WAIT_RESULT=1
  run herdr_submit "pane:1" "short message"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING"* ]]
  # Sent at least once initially, then re-sent on retry.
  send_count="$(grep -c "^agent send" "${HERDR_FAKE_LOG}")"
  [ "${send_count}" -ge 2 ]
}
