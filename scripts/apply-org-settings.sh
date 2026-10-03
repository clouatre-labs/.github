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

# Canonical org community files distributed to .github/<name> in every
# non-archived repo. Add/update-only: created when missing, updated when
# drifted. CODEOWNERS is never overwritten (per-repo overrides are
# respected). Nothing is ever deleted.
COMMUNITY_FILES=(SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md AI_POLICY.md CODEOWNERS)
COMMUNITY_DIR="${BASH_SOURCE[0]%/*}/../org-community"

# Community files sync: PR-based (homebrew-tap pattern). Repo-level main
# branch rulesets block direct pushes to main, even for Integration tokens.
# Instead: create a branch with the app token, commit each drifted file,
# open one PR per repo, and squash-merge it as the app. The org settings
# app (Integration 2978188, clouatre-labs-org-admin) is a bypass-always
# actor on every repo main-branch ruleset, so its merge is not blocked by
# pull_request or required_status_checks rules.

# Classify one community file for a repo. Sets globals: FILE_CLASS
# (missing | drift | current | override) and FILE_SHA (for drift).
classify_community_file() {
  local repo="$1"
  local name="$2"
  local path=".github/${name}"
  local canonical err
  canonical="$(base64 -w0 <"${COMMUNITY_DIR}/${name}")"
  local get_out
  if ! get_out="$(gh api "/repos/${ORG}/${repo}/contents/${path}" 2>&1)"; then
    if grep -q 'HTTP 404' <<<"${get_out}"; then
      FILE_CLASS="missing"
      FILE_SHA=""
    else
      echo "FAILED: community file ${name} for ${repo}: ${get_out}"
      return 1
    fi
  else
    # The API returns the content base64-encoded, possibly newline-wrapped,
    # so strip newlines before decoding.
    local existing
    existing="$(jq -r '.content' <<<"${get_out}" | tr -d '\n' | base64 -d | base64 -w0)"
    FILE_SHA="$(jq -r '.sha' <<<"${get_out}")"
    if [[ "${existing}" == "${canonical}" ]]; then
      FILE_CLASS="current"
    elif [[ "${name}" == "CODEOWNERS" ]]; then
      FILE_CLASS="override"
    else
      FILE_CLASS="drift"
    fi
  fi
  return 0
}

# Commit one community file to the sync branch. Requires SYNC_BRANCH to
# exist. Never deletes any file.
commit_community_file() {
  local repo="$1"
  local name="$2"
  local path=".github/${name}"
  local canonical sha payload put_err
  canonical="$(base64 -w0 <"${COMMUNITY_DIR}/${name}")"
  # The sha is empty when the file does not exist on the branch (create);
  # otherwise it identifies the blob to replace (update).
  sha="$(gh api "/repos/${ORG}/${repo}/contents/${path}?ref=${SYNC_BRANCH}" --jq '.sha' 2>/dev/null || true)"
  payload="$(jq -n --arg m "chore: sync org community file ${name}" --arg c "${canonical}" --arg b "${SYNC_BRANCH}" --arg s "${sha}" \
    '{message: $m, content: $c, branch: $b} + (if $s == "" then {} else {sha: $s} end)')"
  if ! put_err="$(gh api --method PUT "/repos/${ORG}/${repo}/contents/${path}" \
      --header "Content-Type: application/json" --input - <<<"${payload}" 2>&1 >/dev/null)"; then
    echo "FAILED: community file ${name} for ${repo}: ${put_err}"
    return 1
  fi
  return 0
}

# Merge a PR as the app, retrying briefly while checks settle. The app is a
# bypass-always actor on repo main-branch rulesets, so the merge is expected
# to succeed on the first attempt; retries only cover transient races.
merge_pr() {
  local repo="$1"
  local pr_number="$2"
  local attempt merge_err
  for attempt in 1 2 3; do
    if ! merge_err="$(gh api --method PUT "/repos/${ORG}/${repo}/pulls/${pr_number}/merge" \
        --header "Content-Type: application/json" \
        --input - <<< '{"merge_method": "squash"}' 2>&1 >/dev/null)"; then
      echo "merge attempt ${attempt} for PR ${pr_number} in ${repo} failed: ${merge_err}"
      sleep 20
    else
      return 0
    fi
  done
  echo "FAILED: merge PR ${pr_number} for ${repo}: ${merge_err}"
  return 1
}

# Sync all community files for one repo via branch + PR + squash-merge
# (homebrew-tap pattern). Returns non-zero on failure; the caller counts
# failures and continues. Never deletes any file.
sync_community_files() {
  local repo="$1"
  local changed_files=()
  local changed_actions=()
  local name
  for name in "${COMMUNITY_FILES[@]}"; do
    classify_community_file "${repo}" "${name}" || return 1
    case "${FILE_CLASS}" in
      current)
        echo "skipped .github/${name} (up to date)"
        ;;
      override)
        echo "skipped .github/${name} (per-repo override, not overwritten)"
        echo "- ${repo}: skipped \`.github/${name}\` (per-repo override)" >>"${_COMMUNITY_SUMMARY}"
        ;;
      missing)
        echo "pending .github/${name} (missing on main)"
        changed_files+=("${name}")
        changed_actions+=("created")
        ;;
      drift)
        echo "pending .github/${name} (drifted from canonical)"
        changed_files+=("${name}")
        changed_actions+=("updated")
        ;;
    esac
  done
  if [[ "${#changed_files[@]}" -eq 0 ]]; then
    return 0
  fi

  # Fresh sync branch from main; drop any stale branch from a previous run.
  local sync_branch base_sha
  sync_branch="chore/sync-org-community-files"
  base_sha="$(gh api "/repos/${ORG}/${repo}/git/ref/heads/main" --jq '.object.sha')"
  gh api --method DELETE "/repos/${ORG}/${repo}/git/refs/heads/${sync_branch}" >/dev/null 2>&1 || true
  if ! gh api --method POST "/repos/${ORG}/${repo}/git/refs" \
      --header "Content-Type: application/json" \
      --input - <<<"{\"ref\": \"refs/heads/${sync_branch}\", \"sha\": \"${base_sha}\"}" >/dev/null; then
    echo "FAILED: branch ${sync_branch} for ${repo}"
    return 1
  fi
  SYNC_BRANCH="${sync_branch}"

  local i
  for i in "${!changed_files[@]}"; do
    if ! commit_community_file "${repo}" "${changed_files[${i}]}"; then
      return 1
    fi
    echo "${changed_actions[${i}]} .github/${changed_files[${i}]} on ${sync_branch}"
  done

  # Open the PR (reuse an open PR from a previous partially failed run).
  local pr_number pr_out
  pr_out="$(gh api "/repos/${ORG}/${repo}/pulls?head=${ORG}:${sync_branch}&state=open&base=main" --jq '.[0].number' 2>/dev/null || true)"
  if [[ -n "${pr_out}" && "${pr_out}" != "null" ]]; then
    pr_number="${pr_out}"
  else
    if ! pr_number="$(gh api --method POST "/repos/${ORG}/${repo}/pulls" \
        --header "Content-Type: application/json" \
        --input - <<<"$(jq -n --arg h "${sync_branch}" '{title: "chore: sync org community files", head: $h, base: "main", body: "Syncs org community files to the canonical versions in clouatre-labs/.github (org-community/). Automated pull request; safe to merge."}')" \
        --jq '.number' 2>&1)"; then
      echo "FAILED: open PR for ${repo}: ${pr_number}"
      return 1
    fi
  fi

  if ! merge_pr "${repo}" "${pr_number}"; then
    return 1
  fi
  for i in "${!changed_files[@]}"; do
    echo "- ${repo}: ${changed_actions[${i}]} \`.github/${changed_files[${i}]}\` via PR" >>"${_COMMUNITY_SUMMARY}"
  done
  return 0
}


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
  echo "--- community files (org-community/ -> .github/<name>) ---"
  for cf in "${COMMUNITY_FILES[@]}"; do
    if [[ "${cf}" == "CODEOWNERS" ]]; then
      echo "${cf}: create if missing; update on drift; per-repo overrides never overwritten; changes land via PR"
    else
      echo "${cf}: create if missing; update on drift; changes land via PR"
    fi
  done
  if [[ -n "${TOPICS:-}" ]]; then
    echo "--- desired topics ---"
    echo "${TOPICS}"
  else
    echo "--- topics: TOPICS unset; current topics will be logged only ---"
  fi
  exit 0
fi

FAILED=0

# Step-summary file for the community files sync section; created once.
_COMMUNITY_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  echo "### Community files sync"
  echo
} >>"${_COMMUNITY_SUMMARY}"

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
    local err
    if ! err="$(echo "${label}" | gh api --method POST "/repos/${ORG}/${repo}/labels" \
      --header "Content-Type: application/json" --input - 2>&1 >/dev/null)"; then
      # POST failed (typically 422 already-exists): PATCH by name to update
      # color/description. Never DELETE.
      local name color desc patch_err
      name="$(echo "${label}" | jq -r '.name')"
      color="$(echo "${label}" | jq -r '.color')"
      desc="$(echo "${label}" | jq -r '.description')"
      if ! patch_err="$(echo "${label}" | jq -n --arg n "${name}" --arg c "${color}" --arg d "${desc}" \
        '{name: $n, new_name: $n, color: $c, description: $d}' |
        gh api --method PATCH "/repos/${ORG}/${repo}/labels/$(jq -rn --arg n "${name}" '$n | @uri')" \
          --header "Content-Type: application/json" --input - 2>&1 >/dev/null)"; then
        echo "FAILED: label '${name}' for ${repo}: POST: ${err} | PATCH: ${patch_err}"
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

  # Community files: distribute org-community/ to .github/<name> via
  # branch + PR + squash-merge (repo rulesets block direct pushes to main).
  sync_community_files "${repo}"
}

for repo in $(list_repos); do
  if ! apply_repo "${repo}"; then
    FAILED=$((FAILED + 1))
  fi
done

if [[ "${FAILED}" -gt 0 ]]; then
  echo "Done with ${FAILED} failed repo(s)."
  echo "Failed repo(s): ${FAILED}" >>"${_COMMUNITY_SUMMARY}"
  exit 1
fi

echo "Done."
