#!/usr/bin/env bash
# Configure merge settings and protect `main` for ShipNotes, through the GitHub API.
#
# Settings as code: the same result every time you run it, and a reviewable
# record of WHAT is enforced, instead of 20 checkboxes clicked once in the UI.
#
# Usage (from inside ~/code/shipnotes, gh authenticated):
#   scripts/branch-protection.sh
#   REPO=hamza-tleiss/shipnotes BRANCH=main scripts/branch-protection.sh
#
# Requirements: public repo (branch protection on private repos needs a paid
# plan), admin rights on the repo, and the check names below must match the
# job ids in .github/workflows/ci.yml EXACTLY.
#
# Undo (for example to repair main in an emergency):
#   gh api -X DELETE "repos/{owner}/{repo}/branches/main/protection"
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
BRANCH="${BRANCH:-main}"

echo "==> $REPO: squash merge only, delete merged branches, allow auto-merge"
# Squash only: one PR = one commit on main = one Conventional Commit line.
# That is what makes `git log --oneline` and generated release notes readable.
gh repo edit "$REPO" \
  --enable-squash-merge \
  --enable-merge-commit=false \
  --enable-rebase-merge=false \
  --delete-branch-on-merge \
  --enable-auto-merge

# The squash commit takes the PR TITLE as its message (so lint the PR title,
# not every WIP commit), and the branch's commit messages as the body.
gh api -X PATCH "repos/$REPO" \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=COMMIT_MESSAGES \
  --silent

echo "==> Protecting $BRANCH"
# PUT replaces the whole protection object, so every field is listed here.
#   strict: true                      the PR branch must be up to date with main
#                                     before merging, so CI tested the real result
#   checks[].context                  job ids from ci.yml (no app_id = any app
#                                     that reported this check recently, i.e. Actions)
#   enforce_admins: true              you are admin; the rules apply to you too
#   required_approving_review_count 0 a PR is required, an approval is not
#                                     (you cannot approve your own PR). Raise to 1
#                                     and set require_code_owner_reviews when a
#                                     second person joins.
#   required_linear_history           no merge commits on main
#   required_conversation_resolution  open review threads block the merge
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - --silent <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "test-api" },
      { "context": "build-frontend" },
      { "context": "docker" }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

echo "==> Result"
gh api "repos/$REPO/branches/$BRANCH/protection" --jq '{
  required_checks: [.required_status_checks.checks[].context],
  up_to_date_before_merge: .required_status_checks.strict,
  enforce_admins: .enforce_admins.enabled,
  approvals_required: .required_pull_request_reviews.required_approving_review_count,
  linear_history: .required_linear_history.enabled,
  force_push_allowed: .allow_force_pushes.enabled
}'
