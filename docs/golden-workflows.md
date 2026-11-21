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

- Golden workflows are reusable via `workflow_call` with a `runner_label` input.
  Runner policy, no exceptions: public repos pass a GitHub-hosted label
  (`ubuntu-26.04-arm`; self-hosted runners on public repos let fork PRs run
  code on your hardware), private repos pass `oci-arm`.
- Top-level and job-level `permissions` blocks are always present and minimal.
- All actions are pinned to full commit SHA.
- SARIF publishing happens only in golden workflows; fleet repo stubs never
  upload SARIF directly.
- Deterministic fallback for known upstream bugs: org IP allow lists can
  break the third-party app check-suite webhook in scorecard-action
  (ossf/scorecard#5382); a fallback queries `api.securityscorecards.dev`
  and reports pass-with-warning on 200 or 404, failing on any other error.

- Golden workflow pin alignment is audited weekly by
  `golden-drift-audit.yml` in this repo: it diffs every public repo's
  `*.yml@SHA` pins against the latest commit touching each golden file and,
  on drift, opens one issue per drifted repo and fails so CI Result goes
  red. Remediation is manual (GPG-signed commits); the org Renovate preset
  handles routine bumps between audits.

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
