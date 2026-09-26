#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
S="$(pwd)/actions/terraform-plan/plan.sh"
echo "terraform-plan: backend obrigatório"
d=$(mktemp -d); mkdir -p "$d/environments" && echo 'environment = "dev"' > "$d/environments/dev.tfvars"
# As checagens acontecem antes de qualquer chamada ao terraform.
assert_exit 1 "bucket vazio sem opt-out falha (variable ausente no Environment)" -- env -C "$d" GITHUB_OUTPUT=/dev/null ENVIRONMENT=dev LINT=false BACKEND_BUCKET='' bash "$S"
out=$( (cd "$d" || exit 1; GITHUB_OUTPUT=/dev/null ENVIRONMENT=dev LINT=false BACKEND_BUCKET='' bash "$S") 2>&1 ) || true
assert_eq "1" "$(grep -c 'TF_STATE_BUCKET' <<< "$out")" "mensagem aponta vars.TF_STATE_BUCKET"
assert_exit 1 "bucket sem chave falha" -- env -C "$d" GITHUB_OUTPUT=/dev/null ENVIRONMENT=dev LINT=false BACKEND_BUCKET=b BACKEND_KEY='' bash "$S"
rm -rf "$d"
finish
