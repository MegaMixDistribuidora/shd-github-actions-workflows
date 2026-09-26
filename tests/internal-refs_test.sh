#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "referências internas"
refs=$(grep -rhoE 'MegaMixDistribuidora/shd-github-actions-workflows/(actions/[A-Za-z0-9_-]+|\.github/workflows/[A-Za-z0-9_.-]+)@[^[:space:]"'"'"']+' .github/workflows | sed 's/.*@//' | sort -u)
assert_eq "0" "$(grep -c '^main$' <<< "$refs")" "nenhuma referência interna @main"
assert_eq "1" "$(grep -c . <<< "$refs")" "todas as referências internas na mesma tag"
assert_eq "1" "$(grep -cE '^v[0-9]+$' <<< "$refs")" "a tag é uma major (vN)"
finish
