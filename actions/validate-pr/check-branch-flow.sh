#!/usr/bin/env bash
# Regra de esteira (ADR-13): somente feature/* → dev e dev → main.
set -euo pipefail
: "${HEAD_REF:?HEAD_REF ausente}" "${BASE_REF:?BASE_REF ausente}"
case "$BASE_REF" in
  dev)
    [[ "$HEAD_REF" == feature/* ]] || { echo "::error::PR para 'dev' só a partir de 'feature/*' (origem: '$HEAD_REF')."; exit 1; } ;;
  main)
    [[ "$HEAD_REF" == "dev" ]] || { echo "::error::PR para 'main' só a partir de 'dev' (origem: '$HEAD_REF')."; exit 1; } ;;
  *)
    echo "::error::Base '$BASE_REF' fora do fluxo: PRs só para 'dev' ou 'main'."; exit 1 ;;
esac
echo "Fluxo válido: $HEAD_REF → $BASE_REF"
