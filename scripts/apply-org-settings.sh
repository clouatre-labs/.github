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

# Canonical org community files. Root-level files are created in
# non-archived repos when missing (root is the most visible supported
# location and is what repos already use); existing root files are
# per-repo overrides and never overwritten. Legacy .github/<name> copies
# are migrated to root or deleted: GitHub gives .github/ precedence over
# root, so a leftover copy shadows the repo's own document. Repos without
# their own file inherit the org defaults from the clouatre-labs/.github
# repository. CODEOWNERS is not an inheritable default: it is kept in
# .github/CODEOWNERS per repo, create-if-missing, never overwritten.
# Nothing is ever deleted except shadowing .github/ copies.
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
# Classify one community file for a repo. Root-level files are per-repo
# overrides and never overwritten. Legacy .github/<name> copies are
# migrated to root (GitHub gives .github/ precedence over root, so a
# leftover copy would shadow the repo's own root-level document).
# Sets globals: FILE_CLASS
#   missing  : no root file and no .github/ copy -> create at root
#   migrate  : .github/ copy exists, no root file -> create at root, delete copy
#   cleanup  : root file and .github/ copy both exist -> delete copy
#   override : root file exists, no copy -> nothing to do
# FILE_PATH is the path acted on; FILE_SHA the existing blob sha when needed.
classify_community_file() {
  local repo="$1"
  local name="$2"
  local root_get copy_get
  root_get="$(gh api "/repos/${ORG}/${repo}/contents/${name}" 2>&1)" \
    && FILE_SHA="$(jq -r '.sha' <<<"${root_get}")" \
    || FILE_SHA=""
  if grep -q 'HTTP 404' <<<"${root_get}"; then
    FILE_SHA=""
    copy_get="$(gh api "/repos/${ORG}/${repo}/contents/.github/${name}" 2>&1)"
    if grep -q 'HTTP 404' <<<"${copy_get}"; then
      FILE_CLASS="missing"
    else
      FILE_CLASS="migrate"
      FILE_SHA="$(jq -r '.sha' <<<"${copy_get}")"
    fi
  else
    copy_get="$(gh api "/repos/${ORG}/${repo}/contents/.github/${name}" 2>&1)"
    if grep -q 'HTTP 404' <<<"${copy_get}"; then
      FILE_CLASS="override"
    else
      FILE_CLASS="cleanup"
      FILE_SHA="$(jq -r '.sha' <<<"${copy_get}")"
    fi
  fi
  return 0
}

# Delete one legacy .github/<name> copy on the sync branch. Requires
# SYNC_BRANCH and FILE_SHA to be set to the copy's blob sha.
delete_github_copy() {
  local repo="$1"
  local name="$2"
  local payload put_err
  payload="$(jq -n --arg m "chore: remove shadowing .github/${name} copy" --arg s "${FILE_SHA}" --arg b "${SYNC_BRANCH}" \
    '{message: $m, sha: $s, branch: $b}')"
  if ! put_err="$(gh api --method DELETE "/repos/${ORG}/${repo}/contents/.github/${name}" \
      --header "Content-Type: application/json" --input - <<<"${payload}" 2>&1 >/dev/null)"; then
    echo "FAILED: delete .github/${name} for ${repo}: ${put_err}"
    return 1
  fi
  return 0
}

# Commit the canonical community file to the repo root on the sync branch.
# Requires SYNC_BRANCH. For the migrate class the .github/ copy is deleted
# in the same branch afterwards by the caller. Never deletes root files.
commit_root_file() {
  local repo="$1"
  local name="$2"
  local canonical payload put_err
  canonical="$(base64 -w0 <"${COMMUNITY_DIR}/${name}")"
  payload="$(jq -n --arg m "chore: add org community file ${name} at repository root" --arg c "${canonical}" --arg b "${SYNC_BRANCH}" \
    '{message: $m, content: $c, branch: $b}')"
  if ! put_err="$(gh api --method PUT "/repos/${ORG}/${repo}/contents/${name}" \
      --header "Content-Type: application/json" --input - <<<"${payload}" 2>&1 >/dev/null)"; then
    echo "FAILED: community file ${name} for ${repo}: ${put_err}"
    return 1
  fi
  return 0
}

# Create .github/CODEOWNERS from the canonical template on the sync branch.
# Only called for the missing class; never overwrites an existing file.
commit_github_codeowners() {
  local repo="$1"
  local name="$2"
  local canonical payload put_err
  canonical="$(base64 -w0 <"${COMMUNITY_DIR}/${name}")"
  payload="$(jq -n --arg m "chore: add org CODEOWNERS" --arg c "${canonical}" --arg b "${SYNC_BRANCH}" \
    '{message: $m, content: $c, branch: $b}')"
  if ! put_err="$(gh api --method PUT "/repos/${ORG}/${repo}/contents/.github/${name}" \
      --header "Content-Type: application/json" --input - <<<"${payload}" 2>&1 >/dev/null)"; then
    echo "FAILED: .github/${name} for ${repo}: ${put_err}"
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

# Sync community files for one repo via branch + PR + squash-merge
# (homebrew-tap pattern). Root-level org files are created when missing;
# existing root files are per-repo overrides and never overwritten; legacy
# .github/<name> copies are migrated to root or deleted when they would
# shadow a root file. Returns non-zero on failure; the caller counts
# failures and continues.
sync_community_files() {
  local repo="$1"
  local actions=()
  local name cls
  for name in "${COMMUNITY_FILES[@]}"; do
    classify_community_file "${repo}" "${name}" || return 1
    cls="${FILE_CLASS}"
    case "${name}" in
      CODEOWNERS)
        # CODEOWNERS is not an inheritable default health file: keep the
        # legacy per-repo behavior (create-if-missing in .github/, never
        # overwrite).
        if [[ "${cls}" == "cleanup" || "${cls}" == "migrate" ]]; then
          echo "skipped .github/${name} (per-repo override, not overwritten)"
          echo "- ${repo}: skipped \`.github/${name}\` (per-repo override)" >>"${_COMMUNITY_SUMMARY}"
        elif [[ "${cls}" == "missing" ]]; then
          actions+=("create-github:${name}")
        else
          echo "skipped ${name} (already present)"
        fi
        continue
        ;;
    esac
    case "${cls}" in
      override)
        echo "skipped ${name} (per-repo root override, not overwritten)"
        ;;
      missing)
        echo "pending ${name} (missing at root)"
        actions+=("create:${name}")
        ;;
      migrate)
        echo "pending ${name} (migrating .github/${name} to root)"
        actions+=("migrate:${name}")
        ;;
      cleanup)
        echo "pending ${name} (removing .github/${name} shadowing root file)"
        actions+=("cleanup:${name}")
        ;;
    esac
  done
  if [[ "${#actions[@]}" -eq 0 ]]; then
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

  local action op file
  for action in "${actions[@]}"; do
    op="${action%%:*}"
    file="${action#*:}"
    case "${op}" in
      create)
        commit_root_file "${repo}" "${file}" || return 1
        echo "created ${file} at repository root on ${sync_branch}"
        ;;
      create-github)
        FILE_SHA=""
        commit_github_codeowners "${repo}" "${file}" || return 1
        echo "created .github/${file} on ${sync_branch}"
        ;;
      migrate)
        commit_root_file "${repo}" "${file}" || return 1
        classify_community_file "${repo}" "${file}" || return 1
        delete_github_copy "${repo}" "${file}" || return 1
        echo "migrated ${file} from .github/ to repository root on ${sync_branch}"
        ;;
      cleanup)
        # Re-classify to refresh FILE_SHA: it is a global overwritten by
        # each classification, and earlier actions in this loop may have
        # changed it since the classification pass.
        classify_community_file "${repo}" "${file}" || return 1
        delete_github_copy "${repo}" "${file}" || return 1
        echo "removed .github/${file} (shadowed root file) on ${sync_branch}"
        ;;
    esac
  done

  # Open the PR (reuse an open PR from a previous partially failed run).
  local pr_number pr_out
  pr_out="$(gh api "/repos/${ORG}/${repo}/pulls?head=${ORG}:${sync_branch}&state=open&base=main" --jq '.[0].number' 2>/dev/null || true)"
  if [[ -n "${pr_out}" && "${pr_out}" != "null" ]]; then
    pr_number="${pr_out}"
  else
    if ! pr_number="$(gh api --method POST "/repos/${ORG}/${repo}/pulls" \
        --header "Content-Type: application/json" \
        --input - <<<"$(jq -n --arg h "${sync_branch}" '{title: "chore: sync org community files", head: $h, base: "main", body: "Places org community files at the repository root and removes shadowing .github/ copies. Canonical defaults live in clouatre-labs/.github. Automated pull request; safe to merge."}')" \
        --jq '.number' 2>&1)"; then
      echo "FAILED: open PR for ${repo}: ${pr_number}"
      return 1
    fi
  fi

  if ! merge_pr "${repo}" "${pr_number}"; then
    return 1
  fi
  echo "- ${repo}: community files synced via PR" >>"${_COMMUNITY_SUMMARY}"
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
      echo "${cf}: create if missing in .github/; per-repo overrides never overwritten; changes land via PR"
    else
      echo "${cf}: create if missing at repository root; per-repo overrides never overwritten; shadowing .github/ copies migrated or removed; changes land via PR"
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
