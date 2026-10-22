# ShipNotes Makefile, Module 01 version (host deployment with systemd + nginx).
# Module 02 replaces most targets with Docker equivalents; keep the habit:
# one short, memorable command per task, the same for you and for CI.
#
# Recipes must be indented with a TAB, not spaces.
-include .env

SHELL         := /usr/bin/env bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

COMPOSE        ?= docker compose
GIT_SHA        := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)
# Tag for build/push: always the commit. `latest` is produced for local use
# only and is never pushed (course convention, COURSE_SPEC.md section 4).
TAG            ?= sha-$(GIT_SHA)
REGISTRY       := ghcr.io/$(GITHUB_USER)
API_IMAGE      := $(REGISTRY)/shipnotes-api
FRONTEND_IMAGE := $(REGISTRY)/shipnotes-frontend
# Service filter for `make logs S=api`
S              ?=

.PHONY: help up down down-v logs ps test build push lint scan clean check-env

SERVICE := shipnotes-api

.PHONY: help setup deploy health status logs errors restart backup lint test
# -h: MAKEFILE_LIST holds two files (.env and Makefile); without -h grep
# prefixes every match with "Makefile:" and the help shows the file name.
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
##old
# help: ## List targets
# 	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

up: ## Build if needed, start the stack (compose.yaml + override) and wait until healthy
	$(COMPOSE) up -d --build --wait

down: ## Stop and remove containers and network; KEEP the database volume
	$(COMPOSE) down

down-v: ## Like down, but also delete the database volume (all notes are lost)
	$(COMPOSE) down -v

ps: ## Show services with state and health
	$(COMPOSE) ps

build: check-env ## Build production images tagged $(TAG) and latest
	docker build --build-arg APP_VERSION=$(TAG) -t $(API_IMAGE):$(TAG) -t $(API_IMAGE):latest api
	docker build -t $(FRONTEND_IMAGE):$(TAG) -t $(FRONTEND_IMAGE):latest frontend
	docker image ls --filter reference='$(REGISTRY)/shipnotes-*'

push: check-env ## Push the $(TAG) images to GHCR (needs: docker login ghcr.io)
	docker push $(API_IMAGE):$(TAG)
	docker push $(FRONTEND_IMAGE):$(TAG)
lint: ## Lint both Dockerfiles with hadolint using .hadolint.yaml
	docker run --rm -v "$$PWD:/work:ro" -w /work hadolint/hadolint hadolint api/Dockerfile frontend/Dockerfile

# The trivy-cache volume keeps the vulnerability DB between runs. --timeout:
# the first DB download is tens of MB and the 5 min default can expire.
scan: check-env ## Scan local images for HIGH/CRITICAL CVEs with trivy (fails on findings)
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
	  aquasec/trivy image --timeout 15m --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(API_IMAGE):latest
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
	  aquasec/trivy image --timeout 15m --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(FRONTEND_IMAGE):latest

clean: ## Remove containers, network, volumes AND locally built images of this project
	$(COMPOSE) down -v --rmi local

check-env:
	@test -n "$(GITHUB_USER)" || { echo "GITHUB_USER is empty: cp .env.example .env and edit it"; exit 1; }

setup: ## One-time host setup (packages, user, db, systemd, nginx)
	./scripts/setup-host.sh

deploy: ## Build and deploy the current checkout
	./scripts/deploy-local.sh

health: ## Check readiness through nginx once
	./scripts/healthcheck.sh http://127.0.0.1/ready 1 0

status: ## systemd status of the API
	systemctl status $(SERVICE) --no-pager

logs: ## Follow logs (all services, or one: make logs S=api)
	$(COMPOSE) logs -f --tail=100 $(S)
##linux
# logs: ## Follow API logs as compact JSON
# 	journalctl -u $(SERVICE) -f -o cat | jq -cR 'fromjson? | {time, level, msg, url: .req.url, status: .res.statusCode}'

errors: ## Warnings and errors from the last hour
	journalctl -u $(SERVICE) --since "1 hour ago" -o cat | jq -cR 'fromjson? | select(.level >= 40)'

restart: ## Restart the API
	sudo systemctl restart $(SERVICE)

backup: ## Dump the database to ~/backups/shipnotes
	./scripts/backup-db.sh

# lint: ## shellcheck every script
# 	shellcheck scripts/*.sh

test: ## Run the API unit tests on the host (no database needed)
	cd api && npm test
