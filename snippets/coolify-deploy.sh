#!/usr/bin/env bash
# Stamped deploy for a Coolify application.
#
# Coolify cannot compute the version itself — it exposes neither .git nor the
# commit SHA to the build — so the stamp is computed here and passed in as a
# build-time environment variable.
#
# The important part is the reset at the end. Coolify remembers the last value
# and reuses it for the next build, so a later webhook or UI deploy would
# rebuild new code carrying this deploy's version string: silently, plausibly
# wrong. Resetting to a sentinel means any build that did not come through this
# script reports "unstamped" instead of lying.
#
# Requires: curl, jq, and a Coolify API token.

set -euo pipefail

APP_UUID="${APP_UUID:-$(cat ~/.version-stamp-app-uuid)}"
TOKEN="${COOLIFY_TOKEN:-$(cat ~/.coolify-token)}"
API="${COOLIFY_API:-https://coolify.example.com/api/v1}"
SITE="${SITE:?set SITE to the deployed base URL, e.g. https://app.example.com}"
TZ_NAME="${TZ_NAME:-Africa/Johannesburg}"
SENTINEL="unstamped unknown"

set_version() {
  local payload
  payload="$(jq -nc --arg v "$1" \
    '{key:"APP_VERSION", value:$v, is_preview:false, is_buildtime:true, is_literal:true}')"
  # POST creates it the first time; PATCH updates it thereafter.
  curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d "$payload" "$API/applications/$APP_UUID/envs" >/dev/null 2>&1 ||
  curl -sf -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d "$payload" "$API/applications/$APP_UUID/envs" >/dev/null
}

# Reset on ANY exit, including failure — never leave a live stamp behind for
# some future unrelated build to inherit.
trap 'set_version "$SENTINEL" || true' EXIT

[ -z "$(git status --porcelain)" ] || {
  echo "!! working tree is dirty — the stamp would not match what is deployed" >&2; exit 1; }

[ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}' 2>/dev/null || echo none)" ] || {
  echo "!! HEAD differs from upstream — push first, the platform builds the remote" >&2; exit 1; }

STAMP="$(TZ=$TZ_NAME git log -1 --date=format-local:'%y.%m.%d.%H%M' --format='v%cd %h')"
SHA="${STAMP##* }"
echo "==> stamping $STAMP"
set_version "$STAMP"

DEP="$(curl -s -H "Authorization: Bearer $TOKEN" "$API/deploy?uuid=$APP_UUID&force=false" \
       | jq -r '.deployments[0].deployment_uuid')"
echo "==> deployment $DEP"

for _ in $(seq 1 160); do
  STATUS="$(curl -s -H "Authorization: Bearer $TOKEN" "$API/deployments/$DEP" | jq -r '.status // "unknown"')"
  case "$STATUS" in
    finished) echo "==> build green"; break ;;
    failed|error|cancelled-by-user) echo "!! deployment $STATUS" >&2; exit 1 ;;
  esac
  sleep 5
done

# Assert rather than assume: ask the running app what it thinks it is.
for _ in $(seq 1 30); do
  LIVE="$(curl -s "$SITE/version" | jq -r '.commit // empty' 2>/dev/null || true)"
  [ "$LIVE" = "$SHA" ] && { echo "==> live /version reports $LIVE — matches"; exit 0; }
  sleep 5
done

echo "!! live /version never reported $SHA (last saw: ${LIVE:-nothing})" >&2
exit 1
