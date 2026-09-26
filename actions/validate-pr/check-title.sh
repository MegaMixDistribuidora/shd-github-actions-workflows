#!/usr/bin/env bash
# Título em Conventional Commits, descrição com no mínimo 10 caracteres.
set -euo pipefail
: "${PR_TITLE:?PR_TITLE ausente}"
types='feat|fix|docs|chore|refactor|test|ci|build|perf|style|revert'
if [[ ! "$PR_TITLE" =~ ^($types)(\([a-z0-9._-]+\))?!?:\ .{10,}$ ]]; then
  echo "::error::Título fora do padrão: '<tipo>(escopo opcional)!: descrição com 10+ caracteres'. Tipos: ${types//|/, }."
  exit 1
fi
echo "Título válido."
