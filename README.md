# shd-github-actions-workflows

Workflows reutilizáveis e actions compostas da Mega Mix. Consumidores **sempre** fixam uma tag (`@vX.Y.Z`); a tag congela também as actions internas (o release reescreve as referências internas para a própria tag).

## Catálogo

| Workflow | Chamador | Faz |
| --- | --- | --- |
| `ci-infra-terraform.yml` | PR para `dev`/`main` | plan com lint, comentado no PR |
| `cd-infra-terraform.yml` | push em `dev`/`main` | plan salvo + apply |
| `ci-terraform-module.yml` | PR no repositório de módulos | valida e testa só os módulos alterados |
| `pr-validation.yml` | PR | fluxo `feature/*` → `dev` → `main` e título convencional |
| `release-semantic.yml` | push em `main` | tag `vX.Y.Z` + GitHub Release (ADR-14) |
| `rollback-infra.yml` | issue com label `rollback-approved` | reaplica uma tag |
| `destroy-infra.yml` | issue com label `destroy-approved` | destrói **dev** |

Detalhes em [`docs/workflows/`](docs/workflows) e o contrato do consumidor em [`docs/conventions.md`](docs/conventions.md).

## Chamadores de um repositório de infra

```yaml
# .github/workflows/ci-dev.yml
name: CI Dev
on:
  pull_request:
    branches: [dev]
    types: [opened, edited, synchronize, reopened]
permissions:
  contents: read
jobs:
  pr:
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/pr-validation.yml@vX.Y.Z
  ci:
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/ci-infra-terraform.yml@vX.Y.Z
    with:
      environment: dev
    permissions:
      contents: read
      id-token: write
      pull-requests: write
```

```yaml
# .github/workflows/deploy-dev.yml (deploy-prod.yml: branches [main], environment: prod)
name: Deploy Dev
on:
  push:
    branches: [dev]
    paths: ["terraform-aws/**", ".github/**"]
permissions:
  contents: read
jobs:
  cd:
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@vX.Y.Z
    with:
      environment: dev
    permissions:
      contents: read
      id-token: write
```

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  release:
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/release-semantic.yml@vX.Y.Z
    permissions:
      contents: write
      issues: write
      pull-requests: write
```

## Desenvolvimento

`bash scripts/dev-tools.sh` instala yq, jq, shellcheck e actionlint em `~/.local/bin`. Antes do PR: `actionlint && bash tests/run.sh`.
