# release-semantic.yml

Todo push na `main` gera tag `vX.Y.Z` e GitHub Release (ADR-14): `feat` → minor, breaking → major, qualquer outro tipo → patch. A configuração do semantic-release é gravada pelo próprio workflow — o consumidor não mantém `.releaserc.json`. Nunca commita na `main`.

Permissões do job chamador: `contents: write`, `issues: write`, `pull-requests: write`. Job: `Tag and Release`.
