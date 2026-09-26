#!/usr/bin/env bash
# Em prod, só quem é admin do repositório pode disparar a operação (ex.: rollback por label).
# No plano Free não há required reviewers: esta checagem é a trava de prod fora do merge em main.
# Variáveis: ENVIRONMENT, SENDER (quem aplicou a label), REPOSITORY (org/repo); gh autenticado.
set -euo pipefail
: "${ENVIRONMENT:?ENVIRONMENT ausente}" "${REPOSITORY:?REPOSITORY ausente}"
if [[ "$ENVIRONMENT" != "prod" ]]; then
  echo "Ambiente '$ENVIRONMENT': sem exigência de admin."
  exit 0
fi
[[ -n "${SENDER:-}" ]] || { echo "::error::não foi possível identificar quem disparou a operação."; exit 1; }
permission=$(gh api "repos/${REPOSITORY}/collaborators/${SENDER}/permission" --jq .permission)
if [[ "$permission" != "admin" ]]; then
  echo "::error::operação em prod exige permissão admin; '${SENDER}' tem '${permission}'."
  exit 1
fi
echo "'${SENDER}' é admin: operação em prod autorizada."
