# shd-github-actions-workflows — Workflows reutilizáveis (Design)

**Estado-alvo** deste repositório. Contexto: [PRD](../../../../docs/prd.md) · [Arquitetura](../../../../docs/arquitetura.md) (ADR-11, ADR-13, ADR-14, ADR-15) · [Fundação](../../../../aws-megamix-infra/docs/superpowers/specs/megamix-infra-foundation-design.md)

## 1. Objetivo

`MegaMixDistribuidora/shd-github-actions-workflows` concentra os workflows
reutilizáveis e as actions compostas de todos os repositórios da Mega Mix. Os
repositórios consumidores têm apenas workflows "chamadores" de poucas linhas; a
lógica vive aqui. `SthoreH/shd-github-actions-workflows` é **referência de
código**, não dependência.

Sucesso: fundação, plataforma e o repositório de módulos rodam CI e CD
exclusivamente com workflows desta organização, fixados por tag exata, e as
actions internas seguem a major móvel da mesma versão (§3).

## 2. Decisões

| Decisão | Motivo |
|---|---|
| Repositório **público** | Workflows reutilizáveis de repositório público podem ser chamados por repositórios privados sem configuração extra; não contém segredo |
| `.pipeline.yml` na raiz do consumidor é a fonte da verdade de versões e caminhos | Mesmo contrato da referência, já usado pela fundação |
| Fluxo de branches `feature/*` → `dev` → `main` | Regra do projeto (`.claude/CLAUDE.md` do workspace): nenhum commit direto em `dev`/`main`, toda mudança por PR. PR em `dev` valida contra dev, merge em `dev` aplica em dev; PR em `main` valida contra prod, merge em `main` aplica em prod e gera release |
| Repositório público com rulesets | Repositórios públicos têm rulesets no plano Free: `dev` e `main` exigem PR, checks verdes, sem force push nem deleção, sem bypass |
| Autenticação na AWS só por OIDC | Nenhuma chave estática; `AWS_ROLE_ARN` e `TF_STATE_BUCKET` são **variables** do GitHub Environment (`vars.*`) — não são segredos e já estão configurados assim na fundação e na plataforma |
| Proteção de prod | No plano Free, repositórios privados não têm required reviewers; a proteção de prod é o merge em `main` feito pelo usuário (regra 6 de `git.md`), o hook `guard-git` e, no rollback, a exigência de admin para prod (action `require-admin`) |
| Actions de terceiros em versões que rodam em Node 24 | `checkout@v7`, `configure-aws-credentials@v6`, `setup-terraform@v4`, `github-script@v9`, `setup-node@v7`. A referência usa actions em Node 20, que o GitHub já está forçando para Node 24 |

## 3. Versionamento

**Consumidores** fixam a tag exata (`@vX.Y.Z`) do workflow reutilizável. **Referências internas** (workflow → action deste repositório, workflow → workflow) usam a **major móvel** (`@v1`).

**Por que não congelar as internas por tag exata:** congelar exigiria reescrever `.github/workflows/*.yml` a cada release (`@main` → `@vX.Y.Z`) e publicar esse commit. O GitHub recusa que o `GITHUB_TOKEN` faça push de commit que crie ou altere arquivos de workflow (`refusing to allow a GitHub App to create or update workflow … without workflows permission`), e a alternativa — GitHub App ou token pessoal com permissão de workflows — foi descartada em 2026-09-26 para não manter credencial extra. `uses:` não aceita expressões, então a ref não pode ser escolhida em tempo de execução.

**Consequência aceita:** quem fixa `@v1.1.0` recebe as actions internas da `v1` mais recente. Mudança incompatível em action exige nova major, e o mesmo PR troca todas as referências internas para `@v2`. `tests/internal-refs_test.sh` falha se houver referência interna `@main` ou em majors diferentes.

**Mecanismo do release (sem commit na `main`, sem alterar arquivos):**

1. `scripts/next-version.sh` calcula a próxima versão a partir da última tag `v*` (ADR-14): `!`/`BREAKING CHANGE` → major, `feat` → minor, qualquer outro commit → patch
2. `scripts/tag-release.sh` cria `vX.Y.Z` no commit da `main` e move a major `vX` para ele
3. push de `vX.Y.Z` e push forçado de `vX` (tags apontando para commit existente — permitido ao `GITHUB_TOKEN`)
4. GitHub Release com as notas geradas

**Teste das actions deste repositório:** o CI do próprio repositório usa as actions por caminho local (`uses: ./actions/<nome>`), então uma mudança em action é testada no PR que a altera, sem depender de release.

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
| `ci-infra-terraform.yml` | PR para `dev` (env dev) / `main` (env prod) | parse do `.pipeline.yml` → `fmt -check` → `init` com backend → `validate` → `tflint` → `checkov` em relatório (`--soft-fail`; sem chave de API não há severidade) → `plan` publicado como comentário no PR |
| `cd-infra-terraform.yml` | push em `dev` / `main`; também chamado pelo rollback | parse → replace-tokens → `init` → `plan` salvo → `apply` do plan salvo; input `ref` opcional para reaplicar uma tag |
| `ci-terraform-module.yml` | PR no `shd-terraform-aws-modules` | detecta módulos alterados → `fmt -check`, `validate` de módulos e `examples/*`, `tflint`, `checkov`, `terraform test` |
| `release-semantic.yml` | push em `main` — **todos** os repositórios (ADR-14) | grava a configuração canônica (o consumidor não mantém `.releaserc.json`); semantic-release: `feat` → minor, `BREAKING CHANGE` → major, **qualquer outro tipo → patch** (`releaseRules`), para que todo commit na `main` gere tag `vX.Y.Z` e GitHub Release. Só cria tag e release; nunca commita na `main` |
| `pr-validation.yml` | PR | branch de origem permitida — **somente** `feature/*` → `dev` e `dev` → `main` — e título em Conventional Commits |
| `rollback-infra.yml` | issue com o template de rollback e label `rollback-approved` | lê a tag e o ambiente da issue → chama `cd-infra-terraform` com `ref` = tag → comenta o resultado na issue |
| `destroy-infra.yml` | issue com o template de destroy e label `destroy-approved` | **somente dev**; exige confirmação textual com o nome do repositório; `plan -destroy` + `apply` |

| Action composta | Usada por |
|---|---|
| `parse-config` | todos os workflows de infra |
| `setup-terraform-aws` | assume a role por OIDC e instala a versão do Terraform do `.pipeline.yml` |
| `terraform-plan` / `terraform-apply` | CI e CD de infra |
| `replace-tokens` | CD |
| `validate-pr` | pr-validation |
| `changed-modules` | ci-terraform-module |
| `parse-issue` | rollback e destroy |
| `require-admin` | rollback (prod só por admin) |

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
- Push em `main`: release da §3 (tag exata + major móvel, sem alterar arquivos)

## 7. Documentação

- `README.md` com o catálogo, o fluxo de branches e um exemplo de workflow chamador por tipo de
  repositório
- `docs/conventions.md` com o contrato do `.pipeline.yml`, variables do GitHub Environment, trust
  OIDC esperada e chave de state
- `docs/workflows/<nome>.md` com inputs, secrets e passos de cada workflow

## 8. Verificação

1. CI verde neste repositório (actionlint, shellcheck, autoteste)
2. primeira tag com os workflows (`v1.1.0`) e a major `v1` publicadas no mesmo commit da `main`; nenhuma referência interna `@main`: `git grep -nE "shd-github-actions-workflows/(actions|\\.github/workflows)/[^@]*@main" v1.1.0` retorna vazio
3. Em `shd-terraform-aws-modules`, um PR roda `ci-terraform-module@v1.1.0` com sucesso
4. Na fundação, um PR para `dev` roda `ci-infra-terraform@v1.1.0` e publica o plan no PR

## 9. Riscos aceitos

| Risco | Mitigação |
|---|---|
| Actions internas seguem a major móvel, não a tag exata | Mudança incompatível só em nova major; `tests/internal-refs_test.sh` impede referências misturadas |
| `checkov` barrar a fundação por achados já existentes | Supressões explícitas e comentadas no código (`#checkov:skip=<id>:<motivo>`), nunca desligar o passo |
| Destroy acidental | Somente dev, label + confirmação textual, e os recursos críticos têm `prevent_destroy` |
