#!/usr/bin/env bash
# Apply org-level rulesets for branch and tag protection.
# Usage: apply-org-rulesets.sh [dry_run]
#   dry_run: when "true", list existing org rulesets and exit without creating.
#
# Requires GH_TOKEN to be set with org administration write permissions.

set -euo pipefail

ORG="clouatre-labs"
DRY_RUN="${1:-false}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "=== Dry run: listing existing org rulesets ==="
  gh api --paginate "/orgs/${ORG}/rulesets" --jq '.[] | {id, name, enforcement, target}'
  exit 0
fi

# Returns the ruleset id if a ruleset with the given name exists, empty string otherwise.
get_ruleset_id() {
  local name="$1"
  gh api --paginate "/orgs/${ORG}/rulesets" --jq --arg name "${name}" \
    '.[] | select(.name == $name) | .id' 2>/dev/null || true
}

# ── Ruleset 1: Main Branch Protection ────────────────────────────────────────

RULESET_NAME="Main Branch Protection"
EXISTING_ID="$(get_ruleset_id "${RULESET_NAME}")"

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Ruleset '${RULESET_NAME}' already exists (id=${EXISTING_ID}). Skipping."
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  gh api --method POST "/orgs/${ORG}/rulesets" \
    --header "Content-Type: application/json" \
    --input - <<'EOF'
{
  "name": "Main Branch Protection",
  "target": "branch",
  "enforcement": "evaluate",
  "bypass_actors": [
    {
      "actor_type": "OrganizationAdmin",
      "actor_id": 1,
      "bypass_mode": "always"
    },
    {
      "actor_type": "RepositoryRole",
      "actor_id": 5,
      "bypass_mode": "always"
    },
    {
      "actor_type": "CopilotAgent",
      "actor_id": 38,
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    },
    "repository_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "non_fast_forward" },
    { "type": "deletion" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    { "type": "required_signatures" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "CI Result" }
        ]
      }
    }
  ]
}
EOF
  echo "Ruleset '${RULESET_NAME}' created."
fi

# ── Ruleset 2: Release Tag Protection ────────────────────────────────────────

RULESET_NAME="Release Tag Protection"
EXISTING_ID="$(get_ruleset_id "${RULESET_NAME}")"

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Ruleset '${RULESET_NAME}' already exists (id=${EXISTING_ID}). Skipping."
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  gh api --method POST "/orgs/${ORG}/rulesets" \
    --header "Content-Type: application/json" \
    --input - <<'EOF'
{
  "name": "Release Tag Protection",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_type": "OrganizationAdmin",
      "actor_id": 1,
      "bypass_mode": "always"
    },
    {
      "actor_type": "RepositoryRole",
      "actor_id": 5,
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/tags/v*"],
      "exclude": []
    },
    "repository_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "creation" }
  ]
}
EOF
  echo "Ruleset '${RULESET_NAME}' created."
fi

echo "Done."
