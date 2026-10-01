# Canonical org community files

These files are the canonical, org-wide community health files for
clouatre-labs. `scripts/apply-org-settings.sh` distributes each of them to
`.github/<name>` in every non-archived repository on its next run.

Files: SECURITY.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, AI_POLICY.md,
CODEOWNERS.

Semantics: add/update-only. Files are created when missing and updated when
they drift from the canonical content; nothing is ever deleted. Per-repo
CODEOWNERS overrides are respected and never overwritten by sync.
