#!/usr/bin/env bash
# Reads `supabase status -o env` and writes local-dev credentials
# into apps/web/.env.local and apps/mobile/.env.
#
# Idempotent: re-run any time after `supabase start` / `supabase stop`.

set -euo pipefail

cd "$(dirname "$0")/.."

SUPABASE_BIN="./.bin/supabase"
if [[ ! -x "$SUPABASE_BIN" ]]; then
  if command -v supabase >/dev/null 2>&1; then
    SUPABASE_BIN="$(command -v supabase)"
  else
    echo "error: supabase CLI not found (tried ./.bin/supabase and PATH)" >&2
    exit 1
  fi
fi

STATUS_ENV="$("$SUPABASE_BIN" status -o env 2>/dev/null || true)"
if [[ -z "$STATUS_ENV" ]]; then
  echo "error: 'supabase status' returned nothing. Is the stack running? Try: $SUPABASE_BIN start" >&2
  exit 1
fi

API_URL="$(printf '%s\n' "$STATUS_ENV" | sed -n 's/^API_URL="\(.*\)"$/\1/p')"
ANON_KEY="$(printf '%s\n' "$STATUS_ENV" | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')"
SERVICE_ROLE_KEY="$(printf '%s\n' "$STATUS_ENV" | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p')"

if [[ -z "$API_URL" || -z "$ANON_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  echo "error: could not parse API_URL / ANON_KEY / SERVICE_ROLE_KEY from supabase status" >&2
  printf '%s\n' "$STATUS_ENV" >&2
  exit 1
fi

cat >apps/web/.env.local <<EOF
NEXT_PUBLIC_SUPABASE_URL=$API_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
EOF

cat >apps/mobile/.env <<EOF
EXPO_PUBLIC_SUPABASE_URL=$API_URL
EXPO_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY
EOF

echo "Synced local env:"
echo "  API URL : $API_URL"
echo "  anon    : ${ANON_KEY:0:24}..."
echo "Wrote apps/web/.env.local and apps/mobile/.env"
