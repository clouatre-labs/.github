# Security Policy

## Reporting Security Issues

If you discover a security vulnerability, please **do not** open a public issue.

Instead, please report it privately:

1. **GitHub Security Advisories** - Use the "Security" tab in the affected repository
2. **Direct contact** - Reach out via <https://github.com/clouatre>

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (if available)

## Response Timeline

- We will acknowledge your report within 48 hours
- We will provide a detailed response within 5 business days
- We will work with you to understand and address the issue

## Disclosure Policy

- Please allow reasonable time for us to address the issue before public disclosure
- We will credit you in the fix (unless you prefer to remain anonymous)

Thank you for helping keep Clouatre Labs projects secure.

## Organization Automation Security Decisions

### The `org-app` environment

The `org-app` environment in this repository protects the organization-level
App credentials used by automation workflows (`ORG_APP_PRIVATE_KEY` and
`ORG_APP_CLIENT_ID`). These credentials allow repository administration,
issues, pull requests, and contents writes across the organization.

Audit finding MED-4 split the scheduled path in
`.github/workflows/apply-org-settings.yml` into two jobs:

- The six-hourly `audit` job runs unprivileged (dry-run, no environment), so it
  cannot access `org-app` secrets and only reports drift.
- The privileged `apply` job runs only on push to `main` (touching
  `safe-settings/**`) or on manual dispatch, and targets the `org-app`
  environment, which now requires review by the
  @clouatre-labs/security-reviewers team. Admins cannot bypass the review gate
  (`can_admins_bypass: false`).

Requiring reviewers was previously rejected in dotfiles#1021 because it would
stall the six-hourly cron. That objection no longer applies: the cron no longer
uses the privileged environment, so reviews are only requested when a real
apply is about to run. This is preferable to the prior state, where
organization-level secrets were readable by every scheduled run without any
human review.

### OrganizationAdmin bypass-always on org rulesets (INFO-1)

Organization administrators can always bypass organization rulesets
(INFO-1). This is accepted: two-factor authentication is enforced
organization-wide, and administrators are the operators of this automation by
design.
