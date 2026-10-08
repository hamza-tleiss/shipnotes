# ShipNotes Makefile, Module 01 version (host deployment with systemd + nginx).
# Module 02 replaces most targets with Docker equivalents; keep the habit:
# one short, memorable command per task, the same for you and for CI.
#
# Recipes must be indented with a TAB, not spaces.

SERVICE := shipnotes-api

.PHONY: help setup deploy health status logs errors restart backup lint test

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

setup: ## One-time host setup (packages, user, db, systemd, nginx)
	./scripts/setup-host.sh

deploy: ## Build and deploy the current checkout
	./scripts/deploy-local.sh

health: ## Check readiness through nginx once
	./scripts/healthcheck.sh http://127.0.0.1/ready 1 0

status: ## systemd status of the API
	systemctl status $(SERVICE) --no-pager

logs: ## Follow API logs as compact JSON
	journalctl -u $(SERVICE) -f -o cat | jq -cR 'fromjson? | {time, level, msg, url: .req.url, status: .res.statusCode}'

errors: ## Warnings and errors from the last hour
	journalctl -u $(SERVICE) --since "1 hour ago" -o cat | jq -cR 'fromjson? | select(.level >= 40)'

restart: ## Restart the API
	sudo systemctl restart $(SERVICE)

backup: ## Dump the database to ~/backups/shipnotes
	./scripts/backup-db.sh

lint: ## shellcheck every script
	shellcheck scripts/*.sh

test: ## API unit tests
	cd api && npm test
