# Contributing to visionEAE repositories

These rules apply to **every** repository in the organisation. They are enforced by tooling
(a local `commit-msg` hook and a CI check), not by memory.

## 1. Commit convention

[Conventional Commits](https://www.conventionalcommits.org/) with a fixed type vocabulary.

```
<type>(<optional-scope>): <summary>

<body — why the change is needed; the diff already shows what>

Refs: #123
```

| Part | Rule |
|---|---|
| `type` | `feat` `fix` `refactor` `test` `docs` `build` `ci` `chore` `perf` `style` `revert` |
| `scope` | optional, lowercase kebab-case, names the area touched: `api`, `domain`, `db`, `security`, `config`, `deps`, `docker`, ... |
| `summary` | imperative mood, lowercase first letter, no trailing period, ≤ 72 characters |
| `body` | optional, after one blank line; explains **why** |
| breaking | `feat(api)!: ...` and/or a `BREAKING CHANGE:` footer |

```
feat(security): add refresh token rotation
fix(api): propagate request id on error paths
test(security): cover reuse detection revoking the whole family
build(deps): pin spring boot 3.5.16
chore: bootstrap repository with org conventions
```

**One concern per commit.** If the summary needs an "and", split it.

### Enforcement

Locally, with [lefthook](https://github.com/evilmartians/lefthook) — deliberately **not** in CI,
so no Actions minutes are spent validating messages.

* Each repository ships `lefthook.yml` and `.lefthook/commit-msg/check-message.sh`.
* Activate once per clone: `lefthook install` (done automatically by `bootstrap-repo.sh`, and for
  every Student 360 repository by `make hooks` in `student360-infra`).
* Install lefthook itself with `npm install -g lefthook` (or `brew install lefthook`).
* Commit template: `git config commit.template .gitmessage`.

## 2. Branching and merging

* `main` is always buildable.
* Short-lived branches named `<type>/<slug>`: `feat/refresh-token-rotation`, `fix/request-id-on-errors`.
* One pull request per self-contained functionality (for Student 360°, per phase gate — see
  `student360-infra/docs/implementation-plan.md`). The PR description carries the evidence that
  the functionality works.
* Merge with **rebase** (linear history). Squash merging is disabled: it collapses the
  one-concern-per-commit history we deliberately build.

## 3. Language

English everywhere: code, identifiers, comments, commits, branches, database objects, docs.

## 4. Creating a new repository

```
.github/scripts/bootstrap-repo.sh <repo-name> <java|node|generic> "<description>"
```

It creates the private repository, applies the merge policy, seeds the standard files
(`.editorconfig`, `.gitignore`, `.gitmessage`, `.githooks/commit-msg`, the CI workflow, a README
stub), makes the first conventional commit and pushes `main`.
