#!/usr/bin/env bash
# One-time host setup for ShipNotes on Ubuntu 24.04 (WSL2 or a real server).
#
# Automates everything Labs 1.2 to 1.8 do by hand:
#   packages, system-wide Node, the shipnotes user, directories, PostgreSQL
#   role + database + schema, the root-only env file, the systemd unit and nginx.
#
# Idempotent: running it twice changes nothing the second time. That property
# is the whole idea behind Ansible (Module 4) and Terraform (Module 5).
#
# Usage: scripts/setup-host.sh        (as your normal user; it calls sudo itself)
set -Eeuo pipefail

APP_USER=shipnotes
APP_DIR=/opt/shipnotes
WEB_ROOT=/var/www/shipnotes
ENV_DIR=/etc/shipnotes
ENV_FILE="$ENV_DIR/api.env"
DB_NAME=shipnotes
DB_USER=shipnotes
NODE_MAJOR=22
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

# Run psql as the postgres superuser. cd /tmp avoids the harmless but noisy
# "could not change directory" warning when the postgres user cannot read $PWD.
psql_admin() { (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -qtA "$@"); }

((EUID != 0)) || die "run as your normal user; the script uses sudo where needed"
[[ -f "$REPO_DIR/db/init.sql" ]] || die "run from a ShipNotes checkout (db/init.sql not found)"

# ---------------------------------------------------------------------------
log "Installing packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  nginx postgresql postgresql-client rsync jq curl ca-certificates gnupg openssl >/dev/null

# ---------------------------------------------------------------------------
if ! /usr/bin/node --version 2>/dev/null | grep -q "^v${NODE_MAJOR}\."; then
  log "Installing system-wide Node.js ${NODE_MAJOR} from the NodeSource apt repository"
  sudo install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" |
    sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs >/dev/null
fi
log "System node for the service: $(/usr/bin/node --version) at /usr/bin/node"

# ---------------------------------------------------------------------------
log "Ensuring system user '$APP_USER'"
if ! id "$APP_USER" &>/dev/null; then
  # --system: no password, UID below 1000, no login shell. A user that only runs a service.
  sudo useradd --system --home-dir "$APP_DIR" --no-create-home \
    --shell /usr/sbin/nologin "$APP_USER"
fi

log "Ensuring directories"
# Code and static files belong to root and are only readable by the service.
sudo install -d -o root -g root -m 755 "$APP_DIR" "$APP_DIR/api" "$WEB_ROOT"
sudo install -d -o root -g root -m 750 "$ENV_DIR"

# ---------------------------------------------------------------------------
log "Ensuring PostgreSQL is running"
sudo systemctl enable --now postgresql >/dev/null

if [[ "$(psql_admin -c "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'")" != "1" ]]; then
  log "Creating database role '$DB_USER'"
  psql_admin -c "CREATE ROLE ${DB_USER} LOGIN"
fi
if [[ "$(psql_admin -c "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'")" != "1" ]]; then
  log "Creating database '$DB_NAME'"
  (cd /tmp && sudo -u postgres createdb -O "$DB_USER" "$DB_NAME")
fi

if ! sudo test -f "$ENV_FILE"; then
  log "Generating a database password and writing $ENV_FILE (root, mode 600)"
  # hex output is URL-safe, so it can go straight into DATABASE_URL.
  db_password="$(openssl rand -hex 16)"
  # The password goes through stdin (heredoc), not argv, so it never shows up in `ps`.
  (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -q) <<SQL
ALTER ROLE ${DB_USER} WITH PASSWORD '${db_password}';
SQL
  # umask 077 inside the sudo shell: the file is created 600 from the first byte.
  sudo sh -c "umask 077 && cat > '$ENV_FILE'" <<ENV
PORT=3000
NODE_ENV=production
LOG_LEVEL=info
APP_VERSION=dev
DATABASE_URL=postgres://${DB_USER}:${db_password}@127.0.0.1:5432/${DB_NAME}
ENV
  unset db_password
else
  log "$ENV_FILE already exists; keeping the current password"
fi

log "Applying db/init.sql as '$DB_USER' (idempotent)"
DATABASE_URL="$(sudo grep -E '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)"
# Run as the app role so the table is OWNED by shipnotes. Running it as the
# postgres superuser would create a table the API cannot write to.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$REPO_DIR/db/init.sql"

# ---------------------------------------------------------------------------
log "Installing the systemd unit"
sudo install -m 644 "$REPO_DIR/infra/host/systemd/shipnotes-api.service" \
  /etc/systemd/system/shipnotes-api.service
sudo systemctl daemon-reload
# enable = start at boot. Not started yet: there is no code in /opt until the first deploy.
sudo systemctl enable shipnotes-api >/dev/null 2>&1

# ---------------------------------------------------------------------------
log "Configuring nginx"
sudo install -m 644 "$REPO_DIR/infra/host/nginx/snippets/shipnotes-proxy.conf" \
  /etc/nginx/snippets/shipnotes-proxy.conf
sudo install -m 644 "$REPO_DIR/infra/host/nginx/shipnotes.conf" \
  /etc/nginx/sites-available/shipnotes
sudo ln -sfn /etc/nginx/sites-available/shipnotes /etc/nginx/sites-enabled/shipnotes
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t 2>/dev/null || { sudo nginx -t; die "nginx config test failed"; }
sudo systemctl enable --now nginx >/dev/null 2>&1
sudo systemctl reload nginx

log "Host ready. Next: scripts/deploy-local.sh"
