#!/usr/bin/env bash
# Poll an HTTP endpoint until it answers 2xx, or give up.
#
# Usage:  scripts/healthcheck.sh [URL] [ATTEMPTS] [DELAY_SECONDS]
# Example: scripts/healthcheck.sh http://127.0.0.1/ready 15 2
#
# Exit code 0 = healthy, 1 = still unhealthy after all attempts.
# Progress goes to stderr so stdout stays clean for pipes.
set -Eeuo pipefail

URL="${1:-http://127.0.0.1:3000/ready}"
ATTEMPTS="${2:-10}"
DELAY="${3:-2}"

for ((i = 1; i <= ATTEMPTS; i++)); do
  # -s silent, -o discard the body, -w print only the status code.
  # On "connection refused" curl prints 000 and exits non-zero; "|| true"
  # keeps set -e from killing the script so we can retry.
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" || true)"

  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    echo "healthy: $URL -> $code (attempt $i/$ATTEMPTS)" >&2
    exit 0
  fi

  echo "not healthy yet: $URL -> ${code:-000} (attempt $i/$ATTEMPTS)" >&2
  if ((i < ATTEMPTS)); then
    sleep "$DELAY"
  fi
done

echo "UNHEALTHY: $URL after $ATTEMPTS attempts" >&2
exit 1
