#!/usr/bin/env bash
# Dump the ShipNotes database to a compressed, timestamped file and keep the newest N.
#
# Usage:   scripts/backup-db.sh [BACKUP_DIR]
# Env:     DATABASE_URL  (optional; read from /etc/shipnotes/api.env with sudo if unset)
#          KEEP          (optional; number of backups to keep, default 7)
#
# Restore: gunzip -c <file>.sql.gz | psql "$DATABASE_URL" -v ON_ERROR_STOP=1
#          The dump uses --clean --if-exists, so it drops and recreates objects.
set -Eeuo pipefail

BACKUP_DIR="${1:-$HOME/backups/shipnotes}"
KEEP="${KEEP:-7}"
ENV_FILE=/etc/shipnotes/api.env

die() { echo "ERROR: $*" >&2; exit 1; }

command -v pg_dump >/dev/null || die "pg_dump not found (sudo apt install postgresql-client)"
[[ "$KEEP" =~ ^[0-9]+$ && "$KEEP" -ge 1 ]] || die "KEEP must be a positive integer"

if [[ -z "${DATABASE_URL:-}" ]]; then
  [[ -f "$ENV_FILE" ]] || sudo test -f "$ENV_FILE" || die "DATABASE_URL unset and $ENV_FILE missing"
  DATABASE_URL="$(sudo grep -E '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)"
fi
[[ -n "$DATABASE_URL" ]] || die "could not determine DATABASE_URL"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"   # dumps contain all your data: owner-only

ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/shipnotes-$ts.sql.gz"
tmp="$out.partial"
# If anything below fails, never leave a half-written file that looks like a backup.
trap 'rm -f "$tmp"' EXIT

echo "dumping database to $out" >&2
# pipefail makes this line fail if pg_dump fails, even though gzip succeeds.
pg_dump --clean --if-exists --no-owner --no-privileges "$DATABASE_URL" | gzip -9 >"$tmp"
gzip -t "$tmp"   # verify the archive is readable before trusting it
mv "$tmp" "$out"
echo "backup written: $out ($(du -h "$out" | cut -f1))" >&2

# Retention: list backups newest first, delete everything after the first $KEEP.
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'shipnotes-*.sql.gz' -printf '%T@ %p\n' |
  sort -rn |
  tail -n +"$((KEEP + 1))" |
  cut -d' ' -f2- |
  xargs -r -d '\n' rm -f --

echo "kept the newest $KEEP backups in $BACKUP_DIR" >&2
