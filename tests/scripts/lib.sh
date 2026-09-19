#!/usr/bin/env bash
# Shared helpers for tests/scripts/*.sh — generic assertions plus PATH stubs
# for gh/herdr/bwrap so script behaviour can be tested without network or a
# real herdr session.
#
# Sourcing this file also sets:
#   REPO_ROOT — the harness checkout under test
#   T         — a fresh scratch dir (removed on EXIT)
#   STUB_BIN  — dir prepended to PATH containing stub commands

# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(realpath "$(mktemp -d /tmp/wth-scripts.XXXXXX)")"
STUB_BIN="${T}/bin"
mkdir -p "${STUB_BIN}"
PATH="${STUB_BIN}:${PATH}"
trap 'rm -rf "${T}"' EXIT

expect_rc() { # <name> <rc> <want: 0|nz>
  if [[ "$3" == 0 && "$2" -eq 0 ]] || [[ "$3" == nz && "$2" -ne 0 ]]; then
    ok "$1"
  else
    bad "$1"; printf '       rc=%s\n' "$2"
  fi
}
expect_eq() { # <name> <got> <want>
  [[ "$2" == "$3" ]] && ok "$1" || { bad "$1"; printf '       got=%s want=%s\n' "$2" "$3"; }
}
expect_file() { # <name> <path> <exists|absent>
  if [[ "$3" == exists && -e "$2" ]] || [[ "$3" == absent && ! -e "$2" ]]; then
    ok "$1"
  else
    bad "$1"; printf '       path=%s\n' "$2"
  fi
}
expect_grep()     { [[ "$2" == *"$3"* ]] && ok "$1" || { bad "$1"; printf '       missing: %s\n' "$3"; }; }
expect_not_grep() { [[ "$2" != *"$3"* ]] && ok "$1" || { bad "$1"; printf '       unexpected: %s\n' "$3"; }; }

# --- stub builders -----------------------------------------------------------

# stub_gh — a `gh` whose `repo clone` clones from ${STUB_ORIGIN}/<name>.git
# (a local bare repo) and whose `api` serves canned PR bodies / captures PATCH.
stub_gh() {
  cat > "${STUB_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# record every invocation
echo "gh $*" >> "${GH_STUB_LOG:?}"
if [[ "$1" == "repo" && "$2" == "clone" ]]; then
  slug="$3"; dest="$4"
  git clone "${STUB_ORIGIN:?}/$(basename "${slug}").git" "${dest}"
elif [[ "$1" == "api" ]]; then
  endpoint="$2"
  if [[ "$*" == *"-X PATCH"* ]]; then
    # capture -f body=... value
    for a in "$@"; do [[ "$a" == body=* ]] && printf '%s' "${a#body=}" > "${GH_STUB_BODY_FILE:?}"; done
    echo "Updated PR #1"
  else
    cat "${GH_STUB_BODY_FILE:?}"
  fi
fi
EOF
  chmod +x "${STUB_BIN}/gh"
  export STUB_ORIGIN="${T}/origin"
  mkdir -p "${STUB_ORIGIN}"
  export GH_STUB_LOG="${T}/gh.log" GH_STUB_BODY_FILE="${T}/pr-body.txt"
  : > "${GH_STUB_LOG}"
}

# stub_herdr — records invocations, serves canned JSON for the queries
# spawn-repo-agent.sh makes, and exits 0 for everything else.
stub_herdr() {
  cat > "${STUB_BIN}/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "herdr $*" >> "${HERDR_STUB_LOG:?}"
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"root_pane":{"pane_id":"pane-1"},"workspace_id":"ws-1"}}' ;;
  "tab create")       echo '{"result":{"root_pane":{"pane_id":"pane-1"},"pane":{"pane_id":"pane-1"}}}' ;;
  "pane get")         echo '{"result":{"pane":{"tab_id":"tab-1"}}}' ;;
  *) exit "${HERDR_STUB_RC:-0}" ;;
esac
EOF
  chmod +x "${STUB_BIN}/herdr"
  export HERDR_STUB_LOG="${T}/herdr.log" HERDR_ENV=1
  : > "${HERDR_STUB_LOG}"
}

# stub_bwrap — just enough for `command -v bwrap` to succeed.
stub_bwrap() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_BIN}/bwrap"
  chmod +x "${STUB_BIN}/bwrap"
}

# seed_origin <name> — create a local bare origin with a main branch
# containing one file; stub_gh clones from it.
seed_origin() {
  local name="$1"
  local seed="${T}/seed-${name}"
  git init -q -b main "${seed}"
  git -C "${seed}" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
  git clone -q --bare "${seed}" "${STUB_ORIGIN}/${name}.git"
}

# make_lab <dir> — a lab root with repos/ + worktree/ for WORKTREE_LAB_DIR.
make_lab() { mkdir -p "$1/repos" "$1/worktree"; }
