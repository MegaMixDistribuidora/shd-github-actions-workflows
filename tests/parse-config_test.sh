#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
S=actions/parse-config/parse-config.sh
F=tests/fixtures/pipeline
echo "parse-config"
out=$(mktemp)
GITHUB_OUTPUT=$out bash "$S" "$F/valid.yml" dev
cfg=$(grep '^config=' "$out" | cut -d= -f2-)
assert_eq "1.14.9" "$(jq -r '."pipe_infra_terraform-version"' <<< "$cfg")" "versão do terraform no JSON"
assert_eq "desenvolvimento" "$(jq -r '.pipe_environment_note' <<< "$cfg")" "chave do ambiente no JSON"
assert_eq "terraform-version=1.14.9" "$(grep '^terraform-version=' "$out")" "output terraform-version"
assert_eq "working-path=terraform-aws" "$(grep '^working-path=' "$out")" "output working-path"
assert_eq "files-to-replace=terraform-aws/app.json" "$(grep '^files-to-replace=' "$out")" "output files-to-replace"

: > "$out"; GITHUB_OUTPUT=$out bash "$S" "$F/valid.yml" prod
assert_eq "null" "$(grep '^config=' "$out" | cut -d= -f2- | jq -r '.pipe_environment_note')" "ambiente vazio não herda chaves de outro"

assert_exit 1 "ambiente não declarado falha" -- env GITHUB_OUTPUT=/dev/null bash "$S" "$F/valid.yml" staging
assert_exit 1 "sem terraform-version falha" -- env GITHUB_OUTPUT=/dev/null bash "$S" "$F/missing-version.yml" dev
assert_exit 1 "arquivo inexistente falha" -- env GITHUB_OUTPUT=/dev/null bash "$S" "$F/nao-existe.yml" dev
rm -f "$out"
finish
