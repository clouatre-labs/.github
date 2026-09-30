#!/usr/bin/env bash
# Apply org-wide repo settings, labels, and topics for all non-archived repos.
# Usage: apply-org-settings.sh [dry_run]
#   dry_run: when "true", list non-archived org repos and the desired-state
#   summary, then exit without making any mutating API call.
#
# Optional env:
#   TOPICS: comma-separated topic list to PUT on every repo. When unset,
#   current topics are fetched and logged but left untouched (the org has no
#   topic standard yet).
#
# Requires GH_TOKEN to be set with repo administration write permissions.

set -euo pipefail

ORG="clouatre-labs"
DRY_RUN="${1:-false}"

# Desired merge/settings state. allow_squash_merge is sent together with the
# squash commit title/message enums in the same PATCH payload to avoid a 422.
SETTINGS_PAYLOAD='{
  "name": "__REPO_NAME__",
  "allow_squash_merge": true,
  "squash_merge_commit_title": "COMMIT_OR_PR_TITLE",
  "squash_merge_commit_message": "COMMIT_MESSAGES",
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "has_wiki": false,
  "has_projects": false,
  "has_discussions": false
}'

# Desired label set: add/update-only, never delete. Existing labels not listed
# here are preserved. Colors follow GitHub defaults where they exist.
LABELS_JSON='[
  {"name": "bug",              "color": "d73a4a", "description": "Something is not working"},
  {"name": "documentation",    "color": "0075ca", "description": "Documentation only changes"},
  {"name": "enhancement",      "color": "a2eeef", "description": "New feature or request"},
  {"name": "good first issue", "color": "7057ff", "description": "Good for newcomers"},
  {"name": "help wanted",      "color": "008672", "description": "Extra attention is needed"},
  {"name": "invalid",          "color": "fef2c0", "description": "This does not seem right"},
  {"name": "question",         "color": "d876e3", "description": "Further information is requested"},
  {"name": "wontfix",          "color": "ffffff", "description": "This will not be worked on"},
  {"name": "feat",             "color": "a2eeef", "description": "New feature"},
  {"name": "fix",              "color": "d73a4a", "description": "Bug fix"},
  {"name": "docs",             "color": "0075ca", "description": "Documentation only changes"},
  {"name": "chore",            "color": "d4c5f9", "description": "Maintenance tasks"},
  {"name": "refactor",         "color": "c5def5", "description": "Code change that neither fixes a bug nor adds a feature"},
  {"name": "test",             "color": "bfd4f2", "description": "Adding or correcting tests"},
  {"name": "ci",               "color": "bfdadc", "description": "CI/CD pipeline changes"},
  {"name": "perf",             "color": "e99695", "description": "Performance improvement"},
  {"name": "dependencies",     "color": "0366d6", "description": "Dependency updates"},
  {"name": "security",         "color": "ee0701", "description": "Security-related"},
  {"name": "breaking-change",  "color": "b60205", "description": "Breaking API or behavior change"},
  {"name": "p1",               "color": "b60205", "description": "Priority 1: critical"},
  {"name": "p2",               "color": "d93f0b", "description": "Priority 2: high"},
  {"name": "p3",               "color": "fbca04", "description": "Priority 3: normal"},
  {"name": "epic",             "color": "5319e7", "description": "Cross-repo epic tracking"},
  {"name": "governance",       "color": "3e6b8e", "description": "Org governance and policy"},
  {"name": "infrastructure",   "color": "0e8a16", "description": "Org infrastructure and automation"}
]'

# List non-archived repo names for the org.
list_repos() {
  gh api --paginate "/orgs/${ORG}/repos?per_page=100" --jq '.[] | select(.archived == false) | .name'
}

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "=== Dry run: non-archived repos and desired-state summary ==="
  list_repos
  echo "--- desired settings ---"
  echo "squash-only merges (COMMIT_OR_PR_TITLE / COMMIT_MESSAGES), auto-merge on,"
  echo "delete branch on merge, wiki/projects/discussions off."
  echo "--- desired labels ---"
  echo "${LABELS_JSON}" | jq -r '.[] | "\(.name) #\(.color) \(.description)"'
  if [[ -n "${TOPICS:-}" ]]; then
    echo "--- desired topics ---"
    echo "${TOPICS}"
  else
    echo "--- topics: TOPICS unset; current topics will be logged only ---"
  fi
  exit 0
fi

FAILED=0

# Apply settings, labels, and topics to a single repo. Prints the repo name
# and returns non-zero on failure; the caller counts failures and continues.
apply_repo() {
  local repo="$1"
  echo "=== ${repo} ==="

  # Settings PATCH (name injected per repo).
  local payload="${SETTINGS_PAYLOAD//__REPO_NAME__/${repo}}"
  if ! echo "${payload}" | gh api --method PATCH "/repos/${ORG}/${repo}" \
    --header "Content-Type: application/json" --input - >/dev/null; then
    echo "FAILED: settings PATCH for ${repo}"
    return 1
  fi
  echo "settings patched."

  # Labels: POST for new labels; on 422 (already exists) PATCH by name with
  # color/description. Never DELETE any label.
  local label
  while IFS= read -r label; do
    [[ -z "${label}" ]] && continue
    if ! echo "${label}" | gh api --method POST "/repos/${ORG}/${repo}/labels" \
      --header "Content-Type: application/json" --input - >/dev/null 2>&1; then
      local name color desc
      name="$(echo "${label}" | jq -r '.name')"
      color="$(echo "${label}" | jq -r '.color')"
      desc="$(echo "${label}" | jq -r '.description')"
      if ! echo "${label}" | jq -n --arg n "${name}" --arg c "${color}" --arg d "${desc}" \
        '{name: $n, new_name: $n, color: $c, description: $d}' |
        gh api --method PATCH "/repos/${ORG}/${repo}/labels/$(jq -rn --arg n "${name}" '$n | @uri')" \
          --header "Content-Type: application/json" --input - >/dev/null 2>&1; then
        echo "FAILED: label '${name}' for ${repo}"
        return 1
      fi
    fi
  done < <(echo "${LABELS_JSON}" | jq -c '.[]')
  echo "labels synced."

  # Topics: GET current topics, log them, and only PUT when TOPICS is set.
  # GET and PUT are adjacent with no work in between to minimize the race
  # window; the PUT always sends the full merged list, never a partial one.
  local current
  current="$(gh api "/repos/${ORG}/${repo}/topics" --jq '.names | join(",")' 2>/dev/null || true)"
  echo "current topics: ${current:-none}"
  if [[ -n "${TOPICS:-}" ]]; then
    local merged
    merged="$(printf '%s\n%s\n' "${current}" "${TOPICS}" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort -u | paste -sd, -)"
    gh api --method PUT "/repos/${ORG}/${repo}/topics" \
      --header "Content-Type: application/json" \
      --input - <<<"{\"names\": $(printf '%s' "${merged}" | jq -R 'split(",")')}" >/dev/null
    echo "topics updated: ${merged}"
  fi
}

for repo in $(list_repos); do
  if ! apply_repo "${repo}"; then
    FAILED=$((FAILED + 1))
  fi
done

if [[ "${FAILED}" -gt 0 ]]; then
  echo "Done with ${FAILED} failed repo(s)."
  exit 1
fi

echo "Done."
