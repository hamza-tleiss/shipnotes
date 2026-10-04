# ShipNotes

A deliberately small three-tier web app (React + Node API + PostgreSQL) that exists for one
reason: to be **shipped** in every way a DevOps engineer ships software.

The app is finished. Everything else is yours to build, module by module:

| Module | You add to this repo |
|---|---|
| 01 Linux & networking | `scripts/` (deploy, healthcheck), nginx reverse proxy on a Linux host |
| 02 Docker | `api/Dockerfile`, `frontend/Dockerfile`, `frontend/nginx.conf`, `compose.yaml` |
| 03 CI/CD | `.github/workflows/` (test, build, scan, push images, deploy) |
| 04 AWS | `infra/ansible/` (host configuration), manual cloud deployment |
| 05 Terraform | `infra/terraform/` (VPC, EC2, RDS, S3, IAM, remote state) |
| 06-07 Kubernetes | `deploy/k8s/`, `deploy/helm/shipnotes/`, EKS cluster |
| 08 GitOps | `deploy/argocd/`, promotion between environments |
| 09 Observability | `observability/` (Prometheus, Grafana dashboards, Loki, alerts) |
| 10 Security | OIDC, secrets management, image signing, backups, runbooks |

## Architecture

```
 Browser ──> frontend (nginx :80, serves dist/, proxies /api → api)
                 │
                 └──> api (Node 22 / Express :3000)
                          │   GET /health   liveness (no DB)
                          │   GET /ready    readiness (checks DB)
                          │   GET /metrics  Prometheus format
                          │   GET/POST/DELETE /api/notes
                          └──> postgres (:5432, db "shipnotes")
```

## Run it locally (before Docker, Module 01)

```bash
# 1. Start Postgres (you will replace this with compose in Module 02)
docker run -d --name shipnotes-db -p 5432:5432 \
  -e POSTGRES_USER=shipnotes -e POSTGRES_PASSWORD=shipnotes -e POSTGRES_DB=shipnotes \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  postgres:16-alpine

# 2. API
cd api && npm install && npm run dev        # http://localhost:3000/health

# 3. Frontend (second terminal)
cd frontend && npm install && npm run dev   # http://localhost:5173
```

## API configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `3000` | Listen port |
| `DATABASE_URL` | `postgres://shipnotes:shipnotes@localhost:5432/shipnotes` | Postgres connection string |
| `NODE_ENV` | `development` | Environment name |
| `LOG_LEVEL` | `info` | pino log level (`debug`, `info`, `warn`, `error`) |
| `APP_VERSION` | `dev` | Shown in `/health` and in metrics labels; set it from the git SHA in CI |
| `SKIP_MIGRATE` | unset | `true` when a separate job owns schema migrations |

## Commands

```bash
cd api
npm test            # unit tests, no database needed
npm run migrate     # apply schema (idempotent)
npm start           # production start

cd frontend
npm run build       # typecheck + build to dist/
```
