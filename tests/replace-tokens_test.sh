#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "replace-tokens"
d=$(mktemp -d)
# shellcheck disable=SC2016 # o token literal ${...} é o que está sendo testado
printf '{"role": "${pipe_environment_role-arn}", "keep": "${other}"}\n' > "$d/a.json"
CONFIG='{"pipe_environment_role-arn":"arn:aws:iam::1:role/x"}' FILES="$d/a.json" python3 actions/replace-tokens/replace-tokens.py
# shellcheck disable=SC2016
assert_eq '{"role": "arn:aws:iam::1:role/x", "keep": "${other}"}' "$(cat "$d/a.json")" "token conhecido substituído, desconhecido intacto"
assert_exit 0 "lista vazia é no-op" -- env CONFIG='{}' FILES='' python3 actions/replace-tokens/replace-tokens.py
assert_exit 1 "arquivo listado inexistente falha" -- env CONFIG='{}' FILES="$d/nao-existe" python3 actions/replace-tokens/replace-tokens.py
rm -rf "$d"
finish
