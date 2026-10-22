# syntax=docker/dockerfile:1
# ShipNotes frontend image. Two stages:
#   build    Node + Vite compile the React app into static files (dist/)
#   runtime  nginx serves dist/ and proxies /api/, /health, /ready to the api
#
# The final image contains NO Node, no node_modules and no source: only
# ~300 kB of static files on top of nginx. That is the whole point of
# multi-stage builds.
#
# Build:  docker build -t ghcr.io/<github-user>/shipnotes-frontend:sha-xxxxxxx frontend
# Run:    docker run --rm -p 8080:80 ghcr.io/<github-user>/shipnotes-frontend:sha-xxxxxxx
#         (it needs a reachable host called "api" to proxy to; use Compose)

# ---------------------------------------------------------------------------
# Stage 1: build
# ---------------------------------------------------------------------------
FROM node:22-alpine AS build

WORKDIR /app

# Manifests first for cache (see api/Dockerfile). The frontend needs its
# devDependencies (vite, typescript) to build, so this is a plain npm ci.
COPY package.json package-lock.json ./
RUN npm ci

# Now the source. .dockerignore keeps node_modules and dist out of the context.
COPY . .

# "build": "tsc --noEmit && vite build"  -> type-check, then bundle into dist/
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2: runtime
# nginx:1.30-alpine: stable branch, pinned to minor; patch releases float.
# ---------------------------------------------------------------------------
FROM nginx:1.30-alpine AS runtime

# OCI labels; see api/Dockerfile. Put YOUR repo URL in .source.
LABEL org.opencontainers.image.source="https://github.com/hamza-tleiss/shipnotes" \
      org.opencontainers.image.title="shipnotes-frontend" \
      org.opencontainers.image.description="ShipNotes frontend (React, served by nginx)"

# The image's /etc/nginx/nginx.conf includes /etc/nginx/conf.d/*.conf inside
# its http {} block. Replacing default.conf is the supported way to configure
# a single site without touching the main file.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Only the compiled bundle crosses from the build stage.
COPY --from=build /app/dist /usr/share/nginx/html

# nginx starts as root (to bind :80 and read config), then drops its worker
# processes to the unprivileged "nginx" user. If a platform forbids root
# entirely (Kubernetes PodSecurity "restricted", Module 10), switch the base
# image to nginxinc/nginx-unprivileged:1.30-alpine, which listens on 8080.
EXPOSE 80

# Serve index.html to ourselves. If nginx cannot answer, the container is
# unhealthy. Does not depend on the api: that is what /ready on the api is for.
# 127.0.0.1, not localhost: nginx.conf listens on IPv4 only, and inside some
# containers "localhost" resolves to ::1 first, which would be refused.
# Exec (JSON) form, as for CMD (hadolint DL3025).
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --start-interval=1s --retries=3 \
  CMD ["wget", "-qO", "/dev/null", "http://127.0.0.1/"]

# Same as the base image's CMD; written out so nobody has to guess.
# "daemon off;" keeps nginx in the foreground: a container lives exactly as
# long as its PID 1. nginx handles SIGTERM (fast stop) and SIGQUIT (graceful).
CMD ["nginx", "-g", "daemon off;"]
