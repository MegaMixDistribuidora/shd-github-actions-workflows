#!/usr/bin/env bash
# fmt → init → validate → (tflint, checkov) → plan salvo. Roda no diretório do Terraform.
# Variáveis: ENVIRONMENT, BACKEND_BUCKET, BACKEND_KEY, LINT, DESTROY e REQUIRE_BACKEND
# (padrão true; só o autoteste usa false para rodar sem backend).
set -euo pipefail
: "${ENVIRONMENT:?}" "${LINT:=true}" "${DESTROY:=false}" "${REQUIRE_BACKEND:=true}"
var_file="environments/${ENVIRONMENT}.tfvars"
[[ -f "$var_file" ]] || { echo "::error::$var_file não encontrado."; exit 1; }
if [[ "$REQUIRE_BACKEND" == "true" && -z "${BACKEND_BUCKET:-}" ]]; then
  echo "::error::bucket de state vazio: defina a variable TF_STATE_BUCKET (vars.TF_STATE_BUCKET) no GitHub Environment '${ENVIRONMENT}'."
  exit 1
fi

terraform fmt -check -recursive
if [[ -n "${BACKEND_BUCKET:-}" ]]; then
  : "${BACKEND_KEY:?BACKEND_KEY ausente}"
  terraform init -input=false -lock-timeout=5m \
    -backend-config="bucket=${BACKEND_BUCKET}" -backend-config="key=${BACKEND_KEY}"
else
  terraform init -input=false -backend=false
fi
terraform validate -no-color

if [[ "$LINT" == "true" ]]; then
  curl -sSfL https://raw.githubusercontent.com/terraform-linters/tflint/v0.64.0/install_linux.sh | TFLINT_VERSION=v0.64.0 bash >/dev/null
  tflint --init >/dev/null && tflint --recursive --format compact
  # Sem chave de API o checkov não tem severidade: relatório sem falhar o job.
  pipx run checkov==3.3.19 -d . --framework terraform --quiet --compact --soft-fail
fi

plan_args=(-input=false -lock-timeout=5m -no-color -var-file="$var_file" -out=tfplan -detailed-exitcode)
[[ "$DESTROY" == "true" ]] && plan_args+=(-destroy)
set +e
if [[ -n "${BACKEND_BUCKET:-}" ]]; then terraform plan "${plan_args[@]}"; else terraform plan -lock=false "${plan_args[@]}"; fi
code=$?
set -e
case $code in
  0) changes=false ;;
  2) changes=true ;;
  *) echo "::error::terraform plan falhou (exit $code)."; exit "$code" ;;
esac
terraform show -no-color tfplan > tfplan.txt
{
  echo "has-changes=$changes"
  echo "plan-file=$(pwd)/tfplan"
  echo "plan-text=$(pwd)/tfplan.txt"
} >> "$GITHUB_OUTPUT"
{ echo "### Terraform plan — ${ENVIRONMENT}"; echo; grep -E '^Plan:|No changes' tfplan.txt || true; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
