#!/usr/bin/env bash
# Lê o .pipeline.yml do consumidor e publica a configuração do ambiente como outputs.
# Uso: parse-config.sh <arquivo> <ambiente>
set -euo pipefail
file="$1"; env="$2"
[[ -f "$file" ]] || { echo "::error::$file não encontrado na raiz do repositório."; exit 1; }
if [[ "$(yq ".environments | has(\"$env\")" "$file")" != "true" ]]; then
  echo "::error::Ambiente '$env' não declarado em environments do $file."; exit 1
fi
tf_version=$(yq -r '.infra."terraform-version" // ""' "$file")
work_path=$(yq -r '.infra."working-path" // ""' "$file")
[[ -n "$tf_version" ]] || { echo "::error::infra.terraform-version ausente no $file."; exit 1; }
[[ -n "$work_path" ]] || { echo "::error::infra.working-path ausente no $file."; exit 1; }

config=$(ENV_NAME="$env" yq -o=json -I=0 '
  [
    {"runtime": .runtime, "infra": .infra, "environment": .environments[strenv(ENV_NAME)], "tests": .tests, "deploy": .deploy}
    | .. | select(tag != "!!map" and tag != "!!seq")
    | {"key": ("pipe_" + (path | join("_"))), "value": .}
  ] | from_entries' "$file")
files=$(yq -r '.environments."files-to-replace" // [] | join(" ")' "$file")

{
  echo "config=$config"
  echo "terraform-version=$tf_version"
  echo "working-path=$work_path"
  echo "files-to-replace=$files"
} >> "$GITHUB_OUTPUT"
echo "Configuração de '$env' carregada (terraform $tf_version em $work_path)."
