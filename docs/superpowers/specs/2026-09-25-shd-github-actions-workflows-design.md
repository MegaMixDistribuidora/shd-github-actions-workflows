# shd-github-actions-workflows — Workflows reutilizáveis (Design)

**Data:** 2026-09-25
**Status:** Aguardando revisão
**Fase:** 0 (fundação da esteira)
**Relacionados:** [shd-terraform-aws-modules](../../../../shd-terraform-aws-modules/docs/superpowers/specs/2026-09-25-shd-terraform-aws-modules-design.md) ·
[delta da fundação](../../../../aws-megamix-infra/docs/superpowers/specs/2026-09-25-megamix-infra-foundation-delta-design.md) ·
[plataforma](../../../../aws-megamix-infra-platform/docs/superpowers/specs/2026-09-25-megamix-infra-platform-design.md)

## 1. Objetivo

`MegaMixDistribuidora/shd-github-actions-workflows` concentra os workflows
reutilizáveis e as actions compostas de todos os repositórios da Mega Mix. Os
repositórios consumidores têm apenas workflows "chamadores" de poucas linhas; a
lógica vive aqui. `SthoreH/shd-github-actions-workflows` é **referência de
código**, não dependência.

Sucesso: fundação, plataforma e o repositório de módulos rodam CI e CD
exclusivamente com workflows desta organização, fixados por tag, e **fixar a tag
congela o comportamento inteiro** — inclusive das actions internas.

## 2. Decisões

| Decisão | Motivo |
|---|---|
| Repositório **público** | Workflows reutilizáveis de repositório público podem ser chamados por repositórios privados sem configuração extra; não contém segredo |
| `.pipeline.yml` na raiz do consumidor é a fonte da verdade de versões e caminhos | Mesmo contrato da referência, já usado pela fundação |
| Fluxo de branches `dev` → `main` | Mesmo fluxo já usado pela fundação: PR em `dev` valida contra dev, push em `dev` aplica em dev; PR em `main` valida contra prod, push em `main` aplica em prod e gera release |
| Autenticação na AWS só por OIDC | Nenhuma chave estática; `AWS_ROLE_ARN` e `TF_STATE_BUCKET` são secrets do GitHub Environment |
| Prod exige aprovação | Required reviewers no GitHub Environment `prod` de cada consumidor |
| Actions de terceiros em versões que rodam em Node 24 | A referência usa actions em Node 20, que o GitHub já está forçando para Node 24 |

## 3. Versionamento que congela de verdade

**Problema na referência:** o consumidor fixa `ci-infra-terraform.yml@v1.6.0`, mas o workflow
chama `actions/parse-config@main`, `actions/validate-terraform@main` etc. Uma mudança em `main`
altera o comportamento de todos os consumidores sem nova tag.

**Regra:** toda referência a uma action deste repositório dentro de um workflow deste repositório
aponta para uma **tag de versão**, nunca `main`.

**Mecanismo:** no release, antes de criar a tag, o semantic-release executa um passo
(`@semantic-release/exec`, `prepareCmd`) que reescreve
`MegaMixDistribuidora/shd-github-actions-workflows/actions/<nome>@<qualquer-ref>` para
`@v<nova versão>` em `.github/workflows/*.yml`, e `@semantic-release/git` comita a mudança
(`chore(release): vX.Y.Z [skip ci]`) antes da tag. A tag `vX.Y.Z` aponta, portanto, para um
commit cujas referências internas são `@vX.Y.Z`.

**Teste das actions deste repositório:** o CI do próprio repositório (§6) usa as actions por
caminho local (`uses: ./actions/<nome>`), então uma mudança em action é testada no PR que a
altera, sem depender de release.

## 4. `.pipeline.yml` (contrato do consumidor)

Mesmo esquema da referência, sem as seções de Lambda nesta fase:

```yaml
infra:
  terraform-version: "1.14.9"
  working-path: terraform-aws

environments:
  dev: {}
  prod: {}
  # files-to-replace: []   # opcional, substituição de tokens no CD
```

As seções `runtime`, `deploy` e `tests` (Lambda) entram com os workflows de Lambda (§5.2).

## 5. Catálogo

### 5.1 Fase 0 (escopo desta spec)

| Workflow reutilizável | Gatilho no consumidor | Faz |
|---|---|---|
| `ci-infra-terraform.yml` | PR para `dev` (env dev) / `main` (env prod) | parse do `.pipeline.yml` → `fmt -check` → `init` com backend → `validate` → `tflint` → `checkov` (falha em severidade alta) → `plan` publicado como comentário no PR |
| `cd-infra-terraform.yml` | push em `dev` / `main`; também chamado pelo rollback | parse → replace-tokens → `init` → `plan` salvo → `apply` do plan salvo; input `ref` opcional para reaplicar uma tag |
| `ci-terraform-module.yml` | PR no `shd-terraform-aws-modules` | detecta módulos alterados → `fmt -check`, `validate` de módulos e `examples/*`, `tflint`, `checkov`, `terraform test` |
| `release.yml` | push em `main` (consumidores com release) | semantic-release a partir de Conventional Commits |
| `pr-validation.yml` | PR | branch de origem permitida (`feature/*`, `fix/*`, `docs/*`, `chore/*` → `dev`; `dev` ou `hotfix/*` → `main`) e título em Conventional Commits |
| `rollback-infra.yml` | issue com o template de rollback e label `rollback-approved` | lê a tag e o ambiente da issue → chama `cd-infra-terraform` com `ref` = tag → comenta o resultado na issue |
| `destroy-infra.yml` | issue com o template de destroy e label `destroy-approved` | **somente dev**; exige confirmação textual com o nome do repositório; `plan -destroy` + `apply` |

| Action composta | Usada por |
|---|---|
| `parse-config` | todos os workflows de infra |
| `setup-terraform-aws` | assume a role por OIDC e instala a versão do Terraform do `.pipeline.yml` |
| `terraform-plan` / `terraform-apply` | CI e CD de infra |
| `replace-tokens` | CD |
| `validate-pr` | pr-validation |

**Chave de state:** `{nome-do-repositório}/terraform.tfstate` no bucket de `TF_STATE_BUCKET`,
região `sa-east-1`. Mesma convenção já usada pela fundação, para que a migração não mude o
endereço do state.

**Concorrência:** CD usa `concurrency: <repo>-<env>` sem cancelamento — dois applies no mesmo
ambiente nunca rodam juntos, e um apply em andamento nunca é interrompido.

**Permissões:** workflows declaram `contents: read` no topo; só os jobs que assumem role declaram
`id-token: write`; o job de plan que comenta no PR declara `pull-requests: write`.

### 5.2 Fases seguintes (contrato planejado, fora do escopo desta spec)

| Workflow | Fase | Observação |
|---|---|---|
| `ci-lambda-python.yml` / `cd-lambda-python.yml` | 1 (catalog service) | ruff, pytest com cobertura mínima do `.pipeline.yml`; **empacota uma vez** o zip do serviço (arm64) e aplica o Terraform que cria as N funções |
| `ci-amplify-nodejs.yml` / `cd-amplify-terraform.yml` | 1 (loja) | lint, typecheck, build; infra do Amplify por Terraform |

Especificados na spec do primeiro consumidor.

## 6. CI deste repositório

- PR: `actionlint` e `shellcheck` em todos os workflows e scripts; um workflow de autoteste
  roda as actions por caminho local (`./actions/*`) contra um consumidor de exemplo em
  `tests/fixtures/infra-basic/` (Terraform sem backend nem provider real, com `plan` usando
  `-backend=false` e provider mockado)
- Push em `main`: release com o passo de reescrita da §3

## 7. Documentação

- `README.md` com o catálogo, o fluxo de branches e um exemplo de workflow chamador por tipo de
  repositório
- `docs/conventions.md` com o contrato do `.pipeline.yml`, secrets do GitHub Environment, trust
  OIDC esperada e chave de state
- `docs/workflows/<nome>.md` com inputs, secrets e passos de cada workflow

## 8. Verificação

1. CI verde neste repositório (actionlint, shellcheck, autoteste)
2. `v1.0.0` publicada e o commit da tag sem nenhum `@main` interno: `git grep -n "shd-github-actions-workflows/actions/.*@main" v1.0.0` retorna vazio
3. Em `shd-terraform-aws-modules`, um PR roda `ci-terraform-module@v1.0.0` com sucesso
4. Na fundação, um PR para `dev` roda `ci-infra-terraform@v1.0.0` e publica o plan no PR

## 9. Riscos aceitos

| Risco | Mitigação |
|---|---|
| O commit de release escrito pelo bot altera `main` | `[skip ci]` e ruleset permitindo apenas o bot de release no bypass |
| `checkov` barrar a fundação por achados já existentes | Supressões explícitas e comentadas no código (`#checkov:skip=<id>:<motivo>`), nunca desligar o passo |
| Destroy acidental | Somente dev, label + confirmação textual, e os recursos críticos têm `prevent_destroy` |
