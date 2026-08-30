# visionEAE/.github

Organisation defaults and tooling:

* `CONTRIBUTING.md`, `pull_request_template.md` — inherited by every repository that has no own copy.
* `.github/workflows/commit-convention.yml` — reusable workflow called from each repository's CI.
* `scripts/check-commit-message.sh` — canonical commit-message rule (copied into each repo's hook).
* `scripts/bootstrap-repo.sh` — creates a new repository with all of the above applied.
* `templates/` — standard files seeded into new repositories.
* `profile/README.md` — organisation profile.
