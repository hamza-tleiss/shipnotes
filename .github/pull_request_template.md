<!--
PR title = the squash commit message on main = a line in the release notes.
Write it as a Conventional Commit:
  feat: add note search          fix(api): return 404 for unknown note id
  ci: cache docker layers        chore(deps): bump express to 5.2.0
  docs: explain deploy flow      infra: add RDS module
Breaking change: add "!" after the type (feat!: ...) and explain below.
-->

## What and why

<!-- One or two sentences. The diff shows HOW; this explains WHY. Link the issue if any. -->

## How I tested it

<!-- Commands you ran and what you saw. "CI is green" alone is not testing. -->

- [ ] `cd api && npm test`
- [ ] `cd frontend && npm run build`
- [ ] `make up` and the app works at http://localhost:8080 (if containers or config changed)

## Deploy and rollback notes

<!-- Anything the deployer must know: new env var, migration, order of operations.
     How do we roll back if it goes wrong? Write "none" if nothing special. -->

## Checklist

- [ ] PR title follows Conventional Commits
- [ ] No secrets, tokens or `.env` files in the diff
- [ ] Workflow changes keep `permissions:` minimal and actions pinned
- [ ] Docs / README updated if behaviour changed
