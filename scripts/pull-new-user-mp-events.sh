#!/usr/bin/env bash
# Pull Mixpanel Activity Stream events for a user (distinct_id).
# Used by the signup_research skill to enrich new-user analysis.
# Requires MIXPANEL_SERVICE_ACCOUNT_USERNAME, MIXPANEL_SERVICE_ACCOUNT_SECRET,
# and MIXPANEL_PROJECT_ID in ~/.openclaw/.env.
#
# Usage:
#   ./scripts/pull-new-user-mp-events.sh [distinct_id]
#
# Example:
#   ./scripts/pull-new-user-mp-events.sh 42d6fc5c-19b7-4da3-87e6-b01edff8e8f3
#
# To verify from inside the gateway Docker container (mount repo so no rebuild needed):
#   docker compose run --rm --entrypoint bash -v "$(pwd):/app" openclaw-cli -c "./scripts/pull-new-user-mp-events.sh <distinct_id>"
#
# Reference: https://developer.mixpanel.com/reference/activity-stream-query

set -euo pipefail

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
if [[ -f "$CONFIG_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_DIR/.env"
  set +a
fi

USERNAME="${MIXPANEL_SERVICE_ACCOUNT_USERNAME:?MIXPANEL_SERVICE_ACCOUNT_USERNAME must be set in ~/.openclaw/.env}"
SECRET="${MIXPANEL_SERVICE_ACCOUNT_SECRET:?MIXPANEL_SERVICE_ACCOUNT_SECRET must be set in ~/.openclaw/.env}"
PROJECT_ID="${MIXPANEL_PROJECT_ID:?MIXPANEL_PROJECT_ID must be set in ~/.openclaw/.env}"
DISTINCT_ID="${1:-test-distinct-id}"
FROM_DATE="2026-03-01"
TO_DATE="2026-03-02"

DISTINCT_IDS_ENC=$(jq -nc --arg id "$DISTINCT_ID" '[$id]' | jq -sRr @uri)
URL="https://mixpanel.com/api/query/stream/query"
QUERY_STRING="project_id=$PROJECT_ID&distinct_ids=$DISTINCT_IDS_ENC&from_date=$FROM_DATE&to_date=$TO_DATE"

echo "==> Calling Mixpanel Activity Stream API (distinct_id=$DISTINCT_ID, $FROM_DATE to $TO_DATE)"
RESPONSE=$(curl -sS -u "$USERNAME:$SECRET" -H "accept: application/json" "$URL?$QUERY_STRING")
# Filter out events whose name starts with $mp_ (Mixpanel autocapture noise)
# Uses test() with regex since startswith("$mp_") can be unreliable with $ in jq
# Handles both object elements {event,properties} and array elements [event_name,properties]
echo "$RESPONSE" | jq '
  def ev_name:
    if type == "array" then
      (.[0] // .[1].event // .[1].name // "") | tostring
    else
      (.event // .name // .["$event"] // .properties.event // "") | tostring
    end;
  def filter_mp: [.[] | select(ev_name | test("^\\$mp_") | not)];
  if type == "array" then filter_mp
  elif .results then .results |= filter_mp
  elif .data then .data |= filter_mp
  elif .events then .events |= filter_mp
  else . end
'
