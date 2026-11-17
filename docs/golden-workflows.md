# Golden Workflow Methodology

This org standardizes CI through three reusable golden workflows in
`clouatre-labs/.github`:

- `scorecard.yml` - OpenSSF Scorecard analysis with SARIF publishing.
- `security-lint.yml` / `security-lint-sarif.yml` - secret scanning
  (TruffleHog), zizmor audit, REUSE compliance, markdownlint; `-sarif` also
  uploads zizmor findings to code scanning.
- `runner-watchdog.yml` - alerts when `oci-arm` runs stay queued past 20
  minutes; runs on GitHub-hosted runners so it works when self-hosted is down.

## Design rules

- Golden workflows are reusable via `workflow_call` with a `runner_label` input
  so public repos can pick a GitHub-hosted runner.
- Top-level and job-level `permissions` blocks are always present and minimal.
- All actions are pinned to full commit SHA.
- SARIF publishing happens only in golden workflows; fleet repo stubs never
  upload SARIF directly.
- Deterministic fallback for known upstream bugs: org IP allow lists can
  break the third-party app check-suite webhook in scorecard-action
  (ossf/scorecard#5382); a fallback queries `api.securityscorecards.dev`
  and reports pass-with-warning on 200 or 404, failing on any other error.

## Fleet rollout playbook

Inventory the org's repositories, copy the golden workflows into the org
`.github` repo, open one stub PR per repo (weekly cron, `workflow_dispatch`,
minimal permissions, job `uses` the org `.github` workflow at a full commit SHA),
squash-merge on green; drift self-heals via org Renovate preset pinning and the
runner-policy audit.

## Gotchas

- Reference reusable workflows by full commit SHA - never a blob URL, tag, or
  short SHA (zizmor flags this as `impostor-commit`); API-created commits
  need a `Signed-off-by:` trailer to satisfy DCO.
Reusable workflows in a private `.github` repo cannot be called across
organizations, so each org carries its own copy.
