#!/usr/bin/env bash
# Creates a visionEAE repository with the organisation conventions applied.
#
#   bootstrap-repo.sh <repo-name> <java|node|generic> "<description>" [--seed-only]
#
# Without --seed-only: creates the private GitHub repository, sets the merge policy
# (rebase only, delete branch on merge), initialises ../<repo-name>, seeds the standard files
# and installs the lefthook hooks,
# commits and pushes main. With --seed-only: only (re)writes the standard files into an
# existing ../<repo-name> — used to align repositories created before this script existed.
set -euo pipefail

ORG="visionEAE"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates="$here/../templates"

name="${1:?repo name}"; kind="${2:?java|node|generic}"; description="${3:-}"
seed_only="${4:-}"
target="$here/../../$name"

# Convention files are always refreshed; .gitignore and README are written only on creation,
# because they are repository-specific and a re-seed must never clobber them.
seed() {
  mkdir -p "$target/.lefthook/commit-msg"
  cp "$templates/generic/.editorconfig" "$target/.editorconfig"
  cp "$templates/generic/.gitmessage" "$target/.gitmessage"
  if [ ! -f "$target/.gitignore" ]; then
    cp "$templates/$kind/.gitignore" "$target/.gitignore" 2>/dev/null || cp "$templates/generic/.gitignore" "$target/.gitignore"
  fi
  cp "$templates/generic/lefthook.yml" "$target/lefthook.yml"
  cp "$here/check-commit-message.sh" "$target/.lefthook/commit-msg/check-message.sh"
  chmod +x "$target/.lefthook/commit-msg/check-message.sh"
  if [ ! -f "$target/README.md" ]; then
    printf '# %s\n\n%s\n\nConventions: see the organisation [CONTRIBUTING](https://github.com/%s/.github/blob/main/CONTRIBUTING.md).\n' \
      "$name" "$description" "$ORG" > "$target/README.md"
  fi
  git -C "$target" config commit.template .gitmessage
  (cd "$target" && lefthook install >/dev/null)
}

if [ "$seed_only" = "--seed-only" ]; then
  seed; echo "Seeded conventions into $target"; exit 0
fi

gh repo create "$ORG/$name" --private --description "$description" >/dev/null
gh repo edit "$ORG/$name" --enable-squash-merge=false --enable-merge-commit=false \
  --enable-rebase-merge --delete-branch-on-merge >/dev/null
mkdir -p "$target"
git -C "$target" init -q -b main
git -C "$target" remote add origin "git@github.com:$ORG/$name.git"
seed
git -C "$target" add -A
git -C "$target" commit -q -m "chore: bootstrap repository with org conventions" \
  -m "Standard files shared by every visionEAE repository: editorconfig, gitignore, commit template and the lefthook commit-msg hook that enforces the commit convention locally."
git -C "$target" push -q -u origin main
echo "Created https://github.com/$ORG/$name → $target"
