#!/usr/bin/env bash
# Reescreve as referências internas deste repositório (actions e workflows) para @v<versão>.
# Uso: pin-internal-refs.sh <X.Y.Z> <arquivo...>
set -euo pipefail
version="${1:-}"
shift || true
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::versão inválida '${version}' (esperado X.Y.Z)" >&2
  exit 1
fi
pattern='(MegaMixDistribuidora/shd-github-actions-workflows/(actions/[A-Za-z0-9_-]+|\.github/workflows/[A-Za-z0-9_.-]+))@[^[:space:]"'"'"']+'
sed -i -E "s#${pattern}#\1@v${version}#g" "$@"
