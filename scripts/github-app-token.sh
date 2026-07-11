#!/usr/bin/env bash
# Usage: github-app-token.sh <owner>/<repo>
#
# Generates a GitHub App installation access token for the given repository.
# The token is printed to stdout and expires after 1 hour.
#
# Required environment variables:
#   GITHUB_APP_ID               — numeric App ID (Settings → Developer settings → GitHub Apps)
#   GITHUB_APP_PRIVATE_KEY_PATH — path to the App's PEM private key file
#
# Dependencies: bash, openssl, curl, jq (no Python or Node required)
set -euo pipefail

usage() {
  echo "Usage: $0 <owner>/<repo>" >&2
  echo "  Env: GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY_PATH" >&2
  exit 1
}

# Generate a JWT signed with the App's RS256 private key.
# GitHub requires iat/exp claims and the App ID as iss.
generate_jwt() {
  local APP_ID="$1"
  local KEY_PATH="$2"

  local NOW IAT EXP
  NOW="$(date +%s)"
  IAT="$((NOW - 60))"   # allow 60s clock skew
  EXP="$((NOW + 600))"  # 10-minute validity (GitHub max)

  local HEADER PAYLOAD UNSIGNED SIGNATURE
  HEADER="$(printf '{"alg":"RS256","typ":"JWT"}' \
    | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  PAYLOAD="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "${IAT}" "${EXP}" "${APP_ID}" \
    | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  UNSIGNED="${HEADER}.${PAYLOAD}"
  SIGNATURE="$(printf '%s' "${UNSIGNED}" \
    | openssl dgst -sha256 -sign "${KEY_PATH}" \
    | openssl base64 -A | tr '+/' '-_' | tr -d '=')"

  printf '%s.%s' "${UNSIGNED}" "${SIGNATURE}"
}

# Resolve the installation ID for a specific repository.
get_installation_id() {
  local JWT="$1"
  local REPO="$2"
  local RESULT

  RESULT="$(curl -sf \
    -H "Authorization: Bearer ${JWT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO}/installation")"

  printf '%s' "${RESULT}" | jq -r '.id'
}

# Exchange the JWT for a short-lived installation access token.
get_installation_token() {
  local JWT="$1"
  local INSTALL_ID="$2"
  local RESULT

  RESULT="$(curl -sf -X POST \
    -H "Authorization: Bearer ${JWT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/app/installations/${INSTALL_ID}/access_tokens")"

  printf '%s' "${RESULT}" | jq -r '.token'
}

main() {
  [[ $# -ne 1 ]] && usage

  local REPO="$1"
  local APP_ID="${GITHUB_APP_ID:?GITHUB_APP_ID is not set}"
  local KEY_PATH="${GITHUB_APP_PRIVATE_KEY_PATH:?GITHUB_APP_PRIVATE_KEY_PATH is not set}"

  if [[ ! -f "${KEY_PATH}" ]]; then
    echo "Error: private key not found: ${KEY_PATH}" >&2
    exit 1
  fi

  local JWT
  JWT="$(generate_jwt "${APP_ID}" "${KEY_PATH}")"

  local INSTALL_ID
  INSTALL_ID="$(get_installation_id "${JWT}" "${REPO}")"

  if [[ -z "${INSTALL_ID}" || "${INSTALL_ID}" == "null" ]]; then
    echo "Error: GitHub App (id=${APP_ID}) is not installed on ${REPO}." >&2
    echo "  Install it at: https://github.com/apps/<app-slug>/installations/new" >&2
    exit 1
  fi

  local TOKEN
  TOKEN="$(get_installation_token "${JWT}" "${INSTALL_ID}")"

  printf '%s\n' "${TOKEN}"
}

main "$@"
