FROM node:22-alpine AS deps

WORKDIR /app

# Copy ONLY the manifests first. This layer is cached as long as package.json
# and package-lock.json do not change, so editing src/ never re-runs npm ci.
COPY package.json package-lock.json ./

# npm ci: reproducible install from the lockfile (fails if lock and manifest
# disagree, never "resolves" anything). --omit=dev: no test/lint tooling in the
# image. The npm cache (~/.npm) lands in this stage only and is left behind.
RUN npm ci --omit=dev

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM node:22-alpine AS runtime

# Build-time argument -> baked into the image as an environment variable.
# CI passes --build-arg APP_VERSION=sha-abc1234; /health and /metrics expose it.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    NODE_ENV=production \
    PORT=3000

# OCI labels. org.opencontainers.image.source is what makes GHCR link the
# package to your repository (and inherit its visibility and README).

LABEL org.opencontainers.image.source="https://github.com/hamza-tleiss/shipnotes" \
      org.opencontainers.image.title="shipnotes-api" \
      org.opencontainers.image.description="ShipNotes API (Node 22 / Express 5)" \
      org.opencontainers.image.version="${APP_VERSION}"

WORKDIR /app

# Production node_modules from the deps stage, then the application code.
# Files stay owned by root and are only readable by the runtime user: a
# compromised process cannot rewrite its own code or dependencies.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# The official node image ships a "node" user, uid 1000 / gid 1000. Everything
# from here on, including CMD and HEALTHCHECK, runs as that user. Port 3000 is
# above 1024, so no root is needed to bind it.
# Numeric on purpose: Kubernetes `runAsNonRoot: true` (Module 6) can only
# verify a numeric UID; with `USER node` the pod is refused with "image has
# non-numeric user (node), cannot verify user is non-root". hadolint DL3066.
USER 1000:1000

# Documentation only: EXPOSE does not publish anything. -p / ports: does.
EXPOSE 3000

# Docker (and Compose --wait) use this to decide "healthy". /ready checks the
# database, so an api whose db is gone turns unhealthy, not just "running".
# wget is BusyBox wget (part of Alpine; curl is not installed). It exits 1 on
# connection refused or any HTTP error status such as 503, and Docker counts
# any non-zero exit as a failed check.
# Exec (JSON) form: no /bin/sh needed to run the check (hadolint DL3025).
# The response body ends up in `docker inspect` under .State.Health.Log.
# --start-interval probes every 2s during the start period, then every 10s.
# Kubernetes ignores HEALTHCHECK and uses its own probes (Module 6).
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --start-interval=2s --retries=3 \
  CMD ["wget", "-qO-", "http://localhost:3000/ready"]

# Exec form: node is PID 1 and receives SIGTERM directly, so the shutdown()
# handler in src/server.js runs and `docker stop` returns in well under a second.
# Shell form (CMD node src/server.js) would put /bin/sh in front of it.
CMD ["node", "src/server.js"]
