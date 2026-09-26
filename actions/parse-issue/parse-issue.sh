#!/usr/bin/env bash
# Extrai o valor de um campo de issue form ("### <título>" seguido do valor).
set -euo pipefail
field="$1"
: "${ISSUE_BODY:?ISSUE_BODY ausente}"
value=$(printf '%s\n' "$ISSUE_BODY" | tr -d '\r' | awk -v f="### ${field}" '
  $0 == f { found = 1; next }
  found && /^### / { exit }
  found && NF { gsub(/^[ \t]+|[ \t]+$/, ""); print; exit }')
if [[ -z "$value" || "$value" == "_No response_" ]]; then
  echo "::error::campo '${field}' ausente ou vazio na issue." >&2
  exit 1
fi
echo "$value"
