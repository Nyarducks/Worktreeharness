#!/usr/bin/env bash
# Reliable herdr agent-pane messaging.
#
# `herdr agent send` only types text into the target pane's input box; it
# does not submit it. Submitting requires a separate `herdr pane send-keys
# <pane> Enter`, and firing that Enter before the paste has actually landed
# in the input box is a real, observed race — the message is left sitting
# unsubmitted in the Orchestrator's (or a worker's) pane. A flat `sleep 1`
# mitigates but does not eliminate this for longer messages, so herdr_submit
# scales the settle delay with message length and verifies the send by
# waiting for the target pane to flip out of "idle" before giving up.
#
# Oversized messages make that race worse (bigger pastes take longer to
# land) and tend to mean the report should have been a summary in the first
# place. herdr_submit refuses anything over HERDR_REPORT_MAX_CHARS before it
# ever calls `herdr agent send`, so a caller can't retry its way into
# delivering an oversized payload — the send simply never happens.
HERDR_REPORT_MAX_CHARS="${HERDR_REPORT_MAX_CHARS:-800}"

# herdr_submit <target_pane_id> <message>
# Sends <message> to <target_pane_id> and submits it, retrying the Enter
# keypress (and, as a last resort, re-sending the text) if the target pane
# never reports leaving "idle" — i.e. the message never actually submitted.
# Fails fast (no send attempted at all) if <message> exceeds
# HERDR_REPORT_MAX_CHARS chars.
herdr_submit() {
  local target_pane="$1" message="$2"
  local attempt settle

  if (( ${#message} > HERDR_REPORT_MAX_CHARS )); then
    echo "herdr_submit: REFUSED — message is ${#message} chars, over the ${HERDR_REPORT_MAX_CHARS}-char cap. Summarize it: keep TASK-DONE/TASK-BLOCKED/CROSS-REPO-REQUEST reports short and factual, and put full detail (logs, diffs, long explanations) in the PR description or commit body instead of the herdr message. Then call herdr_submit again with the shorter text." >&2
    return 1
  fi

  herdr agent send "${target_pane}" "${message}"

  for attempt in 1 2 3; do
    # Scale the settle delay with message size: a short status ping lands
    # near-instantly, but a long paragraph summary can take longer to land
    # in the input box than a flat 1s allows for.
    settle=$(( 1 + ${#message} / 400 ))
    sleep "${settle}"
    herdr pane send-keys "${target_pane}" Enter

    if herdr agent wait "${target_pane}" --status working --timeout 4000 >/dev/null 2>&1; then
      return 0
    fi

    if [[ "${attempt}" -lt 3 ]]; then
      echo "herdr_submit: pane ${target_pane} still idle after Enter (attempt ${attempt}/3), retrying..." >&2
      # The paste may have been cleared or never landed — re-send the text
      # before the next Enter attempt rather than repeating Enter against a
      # possibly-empty input box.
      herdr agent send "${target_pane}" "${message}"
    fi
  done

  echo "herdr_submit: WARNING — pane ${target_pane} never left 'idle' after 3 send/Enter attempts; the message may still be sitting unsubmitted in its input box. Manual check recommended: herdr pane read ${target_pane} --lines 30" >&2
  return 1
}
