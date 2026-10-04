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
# NOTE: gh api --jq does not support --arg, so the name is interpolated directly.
# Callers pass only static, script-controlled names.
get_ruleset_id() {
  local name="$1"
  gh api --paginate "/orgs/${ORG}/rulesets" --jq ".[] | select(.name == \"${name}\") | .id" 2>/dev/null || true
}

# Returns the required status check context for Main Branch Protection.
# Resolution order: REQUIRED_CHECK_NAME env var, org variable
# REQUIRED_CHECK_NAME (via gh api), then default "DCO".
# The org variable lets repos that post a different check name
# (e.g. homebrew-tap posting "Audit", see issue #38) be handled
# without editing this script.
get_required_check_name() {
  local value="${REQUIRED_CHECK_NAME:-}"
  if [[ -z "${value}" ]]; then
    # Assign inside the condition so a failed lookup (e.g. the App token
    # lacking org-variable read access) leaves value empty instead of
    # capturing gh's error JSON as the check name.
    value="$(gh api "/orgs/${ORG}/actions/variables/REQUIRED_CHECK_NAME" --jq '.value' 2>/dev/null)" || value=""
  fi
  # Accept only sane status-check context characters; anything else falls
  # back to the default rather than corrupting the JSON payload.
  local pat='^[A-Za-z0-9][A-Za-z0-9 ._/-]*$'
  [[ "${value}" =~ ${pat} ]] || value=""
  if [[ -z "${value}" ]]; then
    value="DCO"
  fi
  echo "${value}"
}

# ── Ruleset 1: Main Branch Protection ────────────────────────────────────────

RULESET_NAME="Main Branch Protection"
EXISTING_ID="$(get_ruleset_id "${RULESET_NAME}")"
REQUIRED_CHECK="$(get_required_check_name)"
echo "Required status check: ${REQUIRED_CHECK}"

MAIN_BRANCH_PAYLOAD='{
  "name": "Main Branch Protection",
  "target": "branch",
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
    },
    {
      "actor_type": "Integration",
      "actor_id": 2978188,
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
          { "context": "__REQUIRED_CHECK__" }
        ]
      }
    }
  ]
}'

MAIN_BRANCH_PAYLOAD="${MAIN_BRANCH_PAYLOAD//__REQUIRED_CHECK__/${REQUIRED_CHECK}}"

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Ruleset '${RULESET_NAME}' exists (id=${EXISTING_ID}). Patching..."
  echo "${MAIN_BRANCH_PAYLOAD}" | gh api --method PUT "/orgs/${ORG}/rulesets/${EXISTING_ID}" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' patched."
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  echo "${MAIN_BRANCH_PAYLOAD}" | gh api --method POST "/orgs/${ORG}/rulesets" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' created."
fi

# ── Ruleset 2: Release Tag Protection ────────────────────────────────────────

RULESET_NAME="Release Tag Protection"
EXISTING_ID="$(get_ruleset_id "${RULESET_NAME}")"

RELEASE_TAG_PAYLOAD='{
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
}'

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Ruleset '${RULESET_NAME}' exists (id=${EXISTING_ID}). Patching..."
  echo "${RELEASE_TAG_PAYLOAD}" | gh api --method PUT "/orgs/${ORG}/rulesets/${EXISTING_ID}" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' patched."
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  echo "${RELEASE_TAG_PAYLOAD}" | gh api --method POST "/orgs/${ORG}/rulesets" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' created."
fi

echo "Done."

# ── Ruleset 3: Tag Immutability ────────────────────────────────────────────
# Port of the unique rules from yamaska-rs "Tag immutability" (audit MED-3):
# once a tag exists it cannot be deleted, updated, or re-pointed. Required
# signatures are deliberately NOT ported org-wide to avoid forcing signed
# tags on every repo.

RULESET_NAME="Tag Immutability"
EXISTING_ID="$(get_ruleset_id "${RULESET_NAME}")"

TAG_IMMUTABILITY_PAYLOAD='{
  "name": "Tag Immutability",
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
      "include": ["refs/tags/**"],
      "exclude": []
    },
    "repository_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "update" }
  ]
}'

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Ruleset '${RULESET_NAME}' exists (id=${EXISTING_ID}). Patching..."
  echo "${TAG_IMMUTABILITY_PAYLOAD}" | gh api --method PUT "/orgs/${ORG}/rulesets/${EXISTING_ID}" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' patched."
else
  echo "Creating ruleset '${RULESET_NAME}'..."
  echo "${TAG_IMMUTABILITY_PAYLOAD}" | gh api --method POST "/orgs/${ORG}/rulesets" \
    --header "Content-Type: application/json" \
    --input -
  echo "Ruleset '${RULESET_NAME}' created."
fi

echo "Done."
