#!/usr/bin/env bash
# Roda todos os tests/*_test.sh a partir da raiz do repositório.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
status=0
for t in tests/*_test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
