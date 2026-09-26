#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
D=actions/validate-pr
echo "validate-pr: fluxo de branches"
flow() { HEAD_REF=$1 BASE_REF=$2 bash "$D/check-branch-flow.sh"; }
assert_exit 0 "feature/x → dev" -- flow feature/x dev
assert_exit 0 "dev → main" -- flow dev main
assert_exit 1 "fix/x → dev é recusado" -- flow fix/x dev
assert_exit 1 "feature/x → main é recusado" -- flow feature/x main
assert_exit 1 "hotfix/x → main é recusado" -- flow hotfix/x main
assert_exit 1 "qualquer → outra base é recusado" -- flow feature/x release

echo "validate-pr: título"
title() { PR_TITLE=$1 bash "$D/check-title.sh"; }
assert_exit 0 "feat simples" -- title "feat: adiciona workflow de plan"
assert_exit 0 "escopo e !" -- title "feat(github-oidc)!: remove input legado"
assert_exit 0 "ci" -- title "ci: release automático na main"
assert_exit 1 "sem tipo" -- title "adiciona workflow"
assert_exit 1 "tipo desconhecido" -- title "feature: adiciona workflow"
assert_exit 1 "descrição curta" -- title "fix: typo"
assert_exit 1 "sem espaço após dois-pontos" -- title "fix:corrige o plan"
finish
