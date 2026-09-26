#!/usr/bin/env bash
# Lista os módulos (modules/<nome>) afetados entre dois refs.
set -euo pipefail
base="$1"; head="$2"
changed=$(git diff --name-only "$base" "$head")
if grep -qE '^\.github/' <<< "$changed"; then
  find modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  exit 0
fi
# "|| true": sem arquivo em modules/ ou examples/, o grep sai com 1 e o pipefail derrubaria o script.
{ grep -oE '^(modules|examples)/[^/]+' <<< "$changed" || true; } | cut -d/ -f2 | sort -u | while read -r m; do
  if [[ -d "modules/$m" ]]; then echo "$m"; fi
done
exit 0
