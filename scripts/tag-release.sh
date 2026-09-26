#!/usr/bin/env bash
# Cria a tag vX.Y.Z no commit atual e move a tag major vX para ele (localmente).
# O push fica com o workflow. Nenhum arquivo é alterado: o GITHUB_TOKEN não pode
# fazer push de commit que mexa em .github/workflows, mas pode publicar tags.
# Uso: tag-release.sh <X.Y.Z>
set -euo pipefail
version="${1:-}"
if [[ ! "$version" =~ ^([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::versão inválida '${version}' (esperado X.Y.Z)" >&2
  exit 1
fi
major="v${BASH_REMATCH[1]}"
if git rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
  echo "::error::a tag v${version} já existe." >&2
  exit 1
fi
git tag -a "v${version}" -m "v${version}"
git tag -f -a "$major" -m "$major → v${version}" >/dev/null
echo "v${version} criada; ${major} aponta para ela."
