#!/usr/bin/env bash
# Wait until a TCP port accepts connections (e.g. Postgres before starting the API).
#
# Usage:   scripts/wait-for.sh HOST:PORT [TIMEOUT_SECONDS]
# Example: scripts/wait-for.sh 127.0.0.1:5432 30
#
# Pure bash: uses the /dev/tcp pseudo-device, so it works in minimal images
# that have no nc or curl. Exit 0 when the port is open, 1 on timeout, 2 on bad input.
set -Eeuo pipefail

target="${1:?usage: wait-for.sh HOST:PORT [TIMEOUT_SECONDS]}"
timeout_s="${2:-30}"

host="${target%:*}"   # everything before the last ':'
port="${target##*:}"  # everything after the last ':'

if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]]; then
  echo "invalid target '$target' (expected HOST:PORT)" >&2
  exit 2
fi

start=$SECONDS
# Each probe runs in its own bash under `timeout` so an unroutable host cannot
# hang us. The host and port are passed as arguments, never pasted into code.
# The single quotes are deliberate: $1 and $2 must expand in the CHILD shell.
# shellcheck disable=SC2016
until timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; do
  if ((SECONDS - start >= timeout_s)); then
    echo "timeout after ${timeout_s}s waiting for ${host}:${port}" >&2
    exit 1
  fi
  sleep 1
done

echo "${host}:${port} is accepting connections (waited $((SECONDS - start))s)" >&2
