#!/usr/bin/env bash
# Runtime ownership registry for worktrees delegated through herdr.
#
# Records are intentionally local-only: they coordinate processes on one
# machine and must never be committed with a repository.  The dispatcher owns
# a worktree from the moment it hands the task to a worker until an explicit
# release, so follow-up tasks continue to go to the same delegated workspace.

WORKTREE_OWNERSHIP_REGISTRY_RELATIVE_PATH=".runtime/herdr-worktree-ownership"

worktree_ownership_registry_dir() {
  local harness_root="$1"
  printf '%s/%s\n' "$(realpath -m "$harness_root")" "$WORKTREE_OWNERSHIP_REGISTRY_RELATIVE_PATH"
}

worktree_ownership_key() {
  local worktree_path
  worktree_path="$(realpath -m "$1")"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$worktree_path" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$worktree_path" | shasum -a 256 | awk '{print $1}'
  fi
}

worktree_ownership_record_path() {
  local harness_root="$1" worktree_path="$2"
  printf '%s/%s.owner\n' "$(worktree_ownership_registry_dir "$harness_root")" "$(worktree_ownership_key "$worktree_path")"
}

worktree_ownership_record_value() {
  local record="$1" key="$2"
  [[ -f "$record" ]] || return 1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$record"
}

worktree_ownership_lookup() {
  local harness_root="$1" worktree_path="$2"
  local record expected_path recorded_path
  expected_path="$(realpath -m "$worktree_path")"
  record="$(worktree_ownership_record_path "$harness_root" "$expected_path")"
  [[ -f "$record" ]] || return 1

  recorded_path="$(worktree_ownership_record_value "$record" worktree_path)"
  [[ "$recorded_path" == "$expected_path" ]] || return 1
  printf '%s\n' "$record"
}

worktree_ownership_validate_value() {
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

# worktree_ownership_claim <harness-root> <worktree> <repo> <branch>
#                          <worker-pane> <orchestrator-pane>
# Returns 2 when another orchestrator already owns the worktree.
worktree_ownership_claim() {
  local harness_root="$1" worktree_path="$2" repo="$3" branch="$4"
  local worker_pane="$5" orchestrator_pane="$6"
  local registry record existing existing_orchestrator temp

  for value in "$repo" "$branch" "$worker_pane" "$orchestrator_pane"; do
    if ! worktree_ownership_validate_value "$value"; then
      echo "Error: worktree ownership metadata cannot contain a newline." >&2
      return 1
    fi
  done

  worktree_path="$(realpath -m "$worktree_path")"
  registry="$(worktree_ownership_registry_dir "$harness_root")"
  mkdir -p "$registry"
  chmod 700 "$registry" 2>/dev/null || true

  record="$(worktree_ownership_record_path "$harness_root" "$worktree_path")"
  temp="$(mktemp "$registry/.claim.XXXXXX")"
  chmod 600 "$temp"
  {
    printf 'version=1\n'
    printf 'worktree_path=%s\n' "$worktree_path"
    printf 'repo=%s\n' "$repo"
    printf 'branch=%s\n' "$branch"
    printf 'worker_pane=%s\n' "$worker_pane"
    printf 'orchestrator_pane=%s\n' "$orchestrator_pane"
    printf 'claimed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$temp"
  if existing="$(worktree_ownership_lookup "$harness_root" "$worktree_path")"; then
    existing_orchestrator="$(worktree_ownership_record_value "$existing" orchestrator_pane)"
    if [[ -n "$existing_orchestrator" && "$existing_orchestrator" != "$orchestrator_pane" ]]; then
      rm -f -- "$temp"
      echo "Error: ${worktree_path} is already owned by orchestrator pane ${existing_orchestrator}." >&2
      return 2
    fi
    mv "$temp" "$record"
    return
  fi

  # Atomically publish the first record. A competing Orchestrator may race
  # between the lookup above and this point; hard-link creation fails rather
  # than overwriting its claim, after which we inspect the winner.
  if ln "$temp" "$record" 2>/dev/null; then
    rm -f -- "$temp"
    return
  fi

  if existing="$(worktree_ownership_lookup "$harness_root" "$worktree_path")"; then
    existing_orchestrator="$(worktree_ownership_record_value "$existing" orchestrator_pane)"
    if [[ -n "$existing_orchestrator" && "$existing_orchestrator" != "$orchestrator_pane" ]]; then
      rm -f -- "$temp"
      echo "Error: ${worktree_path} was claimed concurrently by orchestrator pane ${existing_orchestrator}." >&2
      return 2
    fi
    mv "$temp" "$record"
    return
  fi

  rm -f -- "$temp"
  echo "Error: could not publish worktree ownership for ${worktree_path}." >&2
  return 1
}

# worktree_ownership_release <harness-root> <worktree>
worktree_ownership_release() {
  local harness_root="$1" worktree_path="$2"
  local record
  if ! record="$(worktree_ownership_lookup "$harness_root" "$worktree_path")"; then
    echo "No delegated-agent ownership record exists for $(realpath -m "$worktree_path")." >&2
    return 1
  fi
  rm -f -- "$record"
}

# worktree_ownership_record_for_path <harness-root> <target-path>
# Prints the owning record when target-path is inside an owned worktree.
worktree_ownership_record_for_path() {
  local harness_root="$1" target_path="$2"
  local registry record target_path owned_path
  registry="$(worktree_ownership_registry_dir "$harness_root")"
  [[ -d "$registry" ]] || return 1
  target_path="$(realpath -m "$target_path")"

  for record in "$registry"/*.owner; do
    [[ -f "$record" ]] || continue
    owned_path="$(worktree_ownership_record_value "$record" worktree_path || true)"
    [[ -n "$owned_path" ]] || continue
    if [[ "$target_path" == "$owned_path" || "$target_path" == "$owned_path/"* ]]; then
      printf '%s\n' "$record"
      return 0
    fi
  done
  return 1
}

worktree_ownership_current_worker_allows_path() {
  local target_path="$1" worker_path="${HERDR_WORKER_WORKTREE:-}"
  [[ -n "$worker_path" ]] || return 1
  worker_path="$(realpath -m "$worker_path")"
  target_path="$(realpath -m "$target_path")"
  [[ "$target_path" == "$worker_path" || "$target_path" == "$worker_path/"* ]]
}

# worktree_ownership_denial_reason <harness-root> <target-path>
# Prints a clear policy message and succeeds only when an orchestrator should
# be denied access to target-path. A dispatched worker is exempt for its own
# assigned worktree via HERDR_WORKER_WORKTREE.
worktree_ownership_denial_reason() {
  local harness_root="$1" target_path="$2"
  local record repo branch worker_pane

  worktree_ownership_current_worker_allows_path "$target_path" && return 1
  record="$(worktree_ownership_record_for_path "$harness_root" "$target_path")" || return 1
  repo="$(worktree_ownership_record_value "$record" repo)"
  branch="$(worktree_ownership_record_value "$record" branch)"
  worker_pane="$(worktree_ownership_record_value "$record" worker_pane)"

  printf 'Worktree is owned by dispatched herdr agent pane %s (repo=%s branch=%s). Do not modify it from the Orchestrator. Send follow-up work with: scripts/spawn-repo-agent.sh %s %s -- "<task>". Ownership remains until explicitly released with: scripts/spawn-repo-agent.sh --release %s %s.' \
    "$worker_pane" "$repo" "$branch" "$repo" "$branch" "$repo" "$branch"
}
