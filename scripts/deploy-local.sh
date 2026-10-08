#!/usr/bin/env bash
# Build ShipNotes from this git checkout and deploy it to the local host.
#
#   1. install API production dependencies in a throwaway staging directory
#   2. build the frontend
#   3. copy both into place (root-owned, read-only for the service)
#   4. stamp APP_VERSION with the git commit
#   5. restart the service and verify it through nginx, like a real user would
#
# Usage: scripts/deploy-local.sh          (after scripts/setup-host.sh)
# Env:   HEALTH_URL  (default http://127.0.0.1/ready)
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR=/opt/shipnotes
WEB_ROOT=/var/www/shipnotes
ENV_FILE=/etc/shipnotes/api.env
SERVICE=shipnotes-api
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1/ready}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

sudo test -f "$ENV_FILE" || die "$ENV_FILE not found; run scripts/setup-host.sh first"
command -v npm >/dev/null || die "npm not found"

# Version = short commit SHA, with -dirty when there are uncommitted changes.
# Module 3 uses exactly this idea to tag Docker images (sha-a1b2c3d).
VERSION="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)"
if [[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]]; then
  VERSION="${VERSION}-dirty"
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# ---------------------------------------------------------------------------
log "Building API $VERSION"
cp "$REPO_DIR/api/package.json" "$REPO_DIR/api/package-lock.json" "$STAGING/"
cp -r "$REPO_DIR/api/src" "$STAGING/src"
# npm ci: exact versions from the lockfile, fails if package.json and lock disagree.
# --omit=dev: no test or build tools on the server.
(cd "$STAGING" && npm ci --omit=dev --no-audit --no-fund --loglevel=error)

log "Building frontend"
(cd "$REPO_DIR/frontend" && npm ci --no-audit --no-fund --loglevel=error && npm run build --silent)

# ---------------------------------------------------------------------------
log "Installing files"
# --delete removes files that no longer exist in the new build.
# --chown/--chmod: root owns the code; the service user can read but not modify it.
sudo rsync -a --delete --chown=root:root --chmod=D755,F644 "$STAGING/" "$APP_DIR/api/"
sudo rsync -a --delete --chown=root:root --chmod=D755,F644 "$REPO_DIR/frontend/dist/" "$WEB_ROOT/"

log "Setting APP_VERSION=$VERSION"
if sudo grep -q '^APP_VERSION=' "$ENV_FILE"; then
  sudo sed -i "s/^APP_VERSION=.*/APP_VERSION=${VERSION}/" "$ENV_FILE"
else
  echo "APP_VERSION=${VERSION}" | sudo tee -a "$ENV_FILE" >/dev/null
fi

# ---------------------------------------------------------------------------
log "Restarting $SERVICE"
sudo systemctl restart "$SERVICE"

if ! "$REPO_DIR/scripts/healthcheck.sh" "$HEALTH_URL" 15 2; then
  echo "---- last 30 log lines ----" >&2
  sudo journalctl -u "$SERVICE" -n 30 --no-pager >&2 || true
  die "deploy of $VERSION failed its health check"
fi

# Prove the NEW version is the one answering, not a stale process.
running="$(curl -fsS "${HEALTH_URL%/ready}/health" | jq -r '.version')"
[[ "$running" == "$VERSION" ]] || die "expected version $VERSION but /health reports $running"

log "Deployed $VERSION. Open http://localhost (or http://shipnotes.local)"
