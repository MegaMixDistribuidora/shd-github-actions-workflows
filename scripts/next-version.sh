#!/usr/bin/env bash
# Calcula a próxima versão semver a partir da última tag v* (ADR-14).
# A tag pode apontar para um commit da main (release sem reescrita) ou para um
# commit de release FORA da main, cujo pai é o commit da main liberado.
# Saída: X.Y.Z em stdout, ou nada se não houver commit novo desde a tag.
set -euo pipefail

last_tag=$(git tag --list 'v*' --sort=-v:refname | head -n1)
if [[ -z "$last_tag" ]]; then
  echo "1.0.0"
  exit 0
fi

if git merge-base --is-ancestor "$last_tag" HEAD; then
  base="$last_tag"
else
  base=$(git rev-parse "${last_tag}^")
fi
range="${base}..HEAD"
[[ -z "$(git rev-list "$range")" ]] && exit 0

IFS=. read -r major minor patch <<< "${last_tag#v}"
if git log --format=%B "$range" | grep -qE '^BREAKING CHANGE|^[a-z]+(\([^)]*\))?!:'; then
  echo "$((major + 1)).0.0"
elif git log --format=%s "$range" | grep -qE '^feat(\([^)]*\))?:'; then
  echo "${major}.$((minor + 1)).0"
else
  echo "${major}.${minor}.$((patch + 1))"
fi
