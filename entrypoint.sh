#!/usr/bin/env bash
set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo "[autodevice] $*"; }
fail()  { echo "::error::$*"; exit 1; }

# ── Mask the API key ────────────────────────────────────────────────────────

if [[ -n "${INPUT_API_KEY:-}" ]]; then
  echo "::add-mask::${INPUT_API_KEY}"
fi

# ── Validate inputs ─────────────────────────────────────────────────────────

[[ -n "${INPUT_API_KEY:-}" ]]       || fail "api-key is required"
[[ -n "${INPUT_PACKAGE_NAME:-}" ]]  || fail "package-name is required"
[[ -n "${INPUT_BUILD_PATH:-}" ]]    || fail "build-path is required"
[[ -f "${INPUT_BUILD_PATH}" ]]      || fail "File not found: ${INPUT_BUILD_PATH}"
[[ -r "${INPUT_BUILD_PATH}" ]]      || fail "File not readable: ${INPUT_BUILD_PATH}"

API_URL="${INPUT_API_URL:-https://app.autodevice.io}"

# ── Install jq if missing ──────────────────────────────────────────────────

if command -v jq &>/dev/null; then
  info "jq already installed: $(jq --version)"
else
  info "Installing jq…"
  OS_NAME="$(uname -s)"
  if [ "$OS_NAME" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
      brew install --quiet jq
    else
      fail "Homebrew not found on macOS runner; cannot install jq. Please preinstall jq."
    fi
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -qq -y jq
  elif command -v apk &>/dev/null; then
    sudo apk add --no-cache jq || apk add --no-cache jq
  elif command -v yum &>/dev/null; then
    sudo yum install -q -y jq
  elif command -v dnf &>/dev/null; then
    sudo dnf install -q -y jq
  else
    fail "Cannot install jq: no supported package manager found. Please preinstall jq."
  fi

  command -v jq &>/dev/null || fail "Failed to install jq"
  info "jq installed: $(jq --version)"
fi

# ── Git metadata ────────────────────────────────────────────────────────────

# For pull_request events, GITHUB_SHA is a merge commit — extract the actual PR head SHA
PR_HEAD_SHA="$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
COMMIT_SHA="${PR_HEAD_SHA:-${GITHUB_SHA:-}}"
BRANCH="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"
REPO="${GITHUB_REPOSITORY:-}"

# ── File metadata ───────────────────────────────────────────────────────────

FILE_NAME="$(basename "${INPUT_BUILD_PATH}")"

# Cross-platform file size (GNU stat vs BSD stat)
if stat --version &>/dev/null 2>&1; then
  FILE_SIZE="$(stat -c%s "${INPUT_BUILD_PATH}")"
else
  FILE_SIZE="$(stat -f%z "${INPUT_BUILD_PATH}")"
fi

info "File: ${FILE_NAME} (${FILE_SIZE} bytes)"

# ── Step 1 – Start upload ──────────────────────────────────────────────────

echo "::group::Step 1 – Get presigned upload URL"

START_PAYLOAD="$(jq -n --arg fn "${FILE_NAME}" '{file_name: $fn}')"

START_RESPONSE="$(
  curl --fail --silent --show-error \
    -X POST \
    -H "Authorization: Bearer ${INPUT_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${START_PAYLOAD}" \
    "${API_URL}/api/v1/apps/start-upload"
)"

UPLOAD_URL="$(echo "${START_RESPONSE}" | jq -r '.upload_url')"
FILE_PATH="$(echo "${START_RESPONSE}" | jq -r '.file_path')"

[[ -n "${UPLOAD_URL}" && "${UPLOAD_URL}" != "null" ]] || fail "Missing upload_url in start-upload response"
[[ -n "${FILE_PATH}" && "${FILE_PATH}" != "null" ]]   || fail "Missing file_path in start-upload response"

info "Presigned URL obtained"
echo "::endgroup::"

# ── Step 2 – Upload binary ─────────────────────────────────────────────────

echo "::group::Step 2 – Upload binary"

curl --fail --silent --show-error \
  -X PUT \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@${INPUT_BUILD_PATH}" \
  "${UPLOAD_URL}"

info "Upload complete"
echo "::endgroup::"

# ── Step 3 – Confirm upload ────────────────────────────────────────────────

echo "::group::Step 3 – Confirm upload"

CONFIRM_PAYLOAD="$(
  jq -n \
    --arg fp "${FILE_PATH}" \
    --arg fs "${FILE_SIZE}" \
    --arg pn "${INPUT_PACKAGE_NAME}" \
    --arg sha "${COMMIT_SHA}" \
    --arg br "${BRANCH}" \
    --arg repo "${REPO}" \
    '{
      file_path:     $fp,
      file_size:     ($fs | tonumber),
      package_name:  $pn,
      commit_sha:    $sha,
      branch:        $br,
      repository:    $repo
    }'
)"

curl --fail --silent --show-error \
  -X POST \
  -H "Authorization: Bearer ${INPUT_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "${CONFIRM_PAYLOAD}" \
  "${API_URL}/api/v1/apps/confirm-upload"

info "Upload confirmed"
echo "::endgroup::"

info "Done! Build uploaded to autodevice.io"
