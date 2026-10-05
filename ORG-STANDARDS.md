# ORG-STANDARDS

This document describes the organization-wide standards that every
repository in `clouatre-labs` inherits automatically. Repositories should
not need to duplicate these settings; this file is the single source of
truth for what is enforced centrally.

## Org-level rulesets

GitHub organization rulesets apply to all (or selected) repositories
without per-repo configuration. This org maintains two layers:

### Universal baseline (org ruleset)

The org ruleset named `Main Branch Protection` (id `13365825`) applies to
all repositories and targets the `main` branch. It runs in **evaluate**
enforcement, meaning violations are reported in ruleset insights but not
blocked, while the rollout is verified.

Rules enforced:

- `pull_request` - require a pull request before merging
- `non_fast_forward` - prevent force pushes
- `deletion` - prevent branch deletion
- `required_signatures` - require GPG or SSH signed commits
- `required_status_checks` - require the `DCO` check to pass

Bypass actors:

- Organization admins (`OrganizationAdmin`) - bypass always
- Repository role id `5` (write) - bypass always
- The DCO App (`Integration` id `1143301`) - exempt

### Repo-level rulesets (template-repo)

Repositories created from the template repo carry their own
`docs/REPO-STANDARDS.md`, which documents the per-repo ruleset layer. See
that file in the template repository for details.

## Evaluate-then-active rollout

New or changed rules are applied in `evaluate` enforcement first. Once
ruleset insights show the rules are satisfied across the org (no
unexpected violations), enforcement is switched to `active`. This avoids
blocking work while standards converge.

## Commit signing and DCO

All commits must be GPG or SSH signed and include a DCO sign-off. The
`DCO` check is the org-wide required status check. AI agents and bots
that cannot sign commits are handled via squash merges by maintainers;
see [CONTRIBUTING.md](CONTRIBUTING.md#commit-signing-and-merge-strategy)
for the full workflow.

## CI concurrency

GitHub Actions concurrency and `cancel-in-progress` are per-workflow
settings; GitHub offers no org-level enforcement. Repositories in this
org follow one convention:

- Each PR-triggered workflow keeps its OWN workflow-scoped concurrency
  group with `cancel-in-progress: true`, so each workflow cancels its
  own stale runs on a newer push:

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref_name }}
    cancel-in-progress: true
  ```

- Do NOT share one concurrency group across workflows whose runs are
  required checks. Concurrency permits only one run per group; when two
  required workflows start simultaneously on the same group they cancel
  each other and the required checks never report (validated in
  clouatre-labs/clouatre.ca#1692).

- Scheduled and deploy workflows use their own group with
  `cancel-in-progress: false`.

The org standard runner for CI is `ubuntu-26.04-arm`.

## Changing these standards

The org ruleset is managed by `scripts/apply-org-rulesets.sh` and the
`apply-org-rulesets` workflow. To propose a change, open an issue
describing the change, then update the script payload in the same PR as
the documentation change so the next dispatch converges the live ruleset.
