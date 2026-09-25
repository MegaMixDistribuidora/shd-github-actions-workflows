# Workflows reutilizáveis de infra — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar em `MegaMixDistribuidora/shd-github-actions-workflows` os workflows reutilizáveis e as actions compostas de infra Terraform da fase 0, versionados de forma que fixar a tag congele também as actions internas.

**Architecture:** Lógica em scripts bash pequenos (`actions/<nome>/*.sh`, `scripts/*.sh`) com testes em bash puro (`tests/*_test.sh`); actions compostas finas chamando esses scripts; workflows reutilizáveis (`on: workflow_call`) compondo as actions por referência remota `@main`, reescrita para `@vX.Y.Z` no release. O CI do próprio repositório roda lint, testes unitários e um autoteste das actions por caminho local contra um consumidor de exemplo sem AWS.

**Tech Stack:** GitHub Actions (composite + reusable workflows), bash, yq v4, jq, Terraform 1.14.9, tflint v0.64.0, checkov 3.3.19, actionlint 1.7.12, shellcheck, semantic-release 24.

**Spec:** [`docs/superpowers/specs/shd-github-actions-workflows-design.md`](../specs/shd-github-actions-workflows-design.md) · contexto: `megamix-workspace/docs/arquitetura.md` (ADR-11, ADR-13, ADR-14, ADR-15)

## Global Constraints

- Branch de trabalho: `feature/workflows-infra` (nasce de `dev`); PR para `dev`, depois `dev` → `main` (merge em `main` é do usuário)
- Commits e título de PR em Conventional Commits, em português
- Terraform `1.14.9`; região padrão `sa-east-1`
- Credenciais da esteira: `vars.AWS_ROLE_ARN` e `vars.TF_STATE_BUCKET` do GitHub Environment (variables, não secrets)
- Chave de state: `${{ github.event.repository.name }}/terraform.tfstate` — **nunca** com pasta de ambiente
- Versões de actions de terceiros (todas Node 24): `actions/checkout@v7`, `aws-actions/configure-aws-credentials@v6`, `hashicorp/setup-terraform@v4`, `actions/github-script@v9`, `actions/setup-node@v7`
- Ferramentas fixadas: tflint `v0.64.0`, checkov `3.3.19`, actionlint `1.7.12`, yq `v4.53.6`, semantic-release `24`
- Referências internas no código-fonte: `MegaMixDistribuidora/shd-github-actions-workflows/actions/<nome>@main` e `.../.github/workflows/<arquivo>.yml@main`; o release as reescreve para `@vX.Y.Z` num commit fora da `main`
- Nenhum commit na `main` feito por bot; todo commit na `main` gera tag e release (ADR-14)
- Permissões: `contents: read` no topo de todo workflow; `id-token: write` só em job que assume role; `pull-requests: write` só no job que comenta o plan
- Mensagens de erro e comentários em português; nomes de arquivos, inputs e outputs em inglês (kebab-case)
- Checkov em modo relatório (`--soft-fail`): sem chave de API não há severidade para decidir falha

## Review Focus

1. **Tag de release na própria `main`** (a `v1.0.0` deste repositório não precisou de commit de reescrita, então aponta para um commit da `main`): o cálculo da próxima versão não pode recontar esse commit nem gerar release sem commit novo — teste em Task 2.
2. **Título de PR com escopo e `!`** (`feat(github-oidc)!: remove input x`): precisa ser aceito — teste em Task 3.
3. **`.pipeline.yml` sem o ambiente pedido ou sem `infra.terraform-version`**: tem de falhar com mensagem clara, não seguir com valor vazio e rodar `terraform` errado — teste em Task 4.
4. **Corpo de issue com `\r\n`** (issue forms do GitHub): o parser de rollback/destroy precisa extrair ambiente, tag e confirmação mesmo assim — teste em Task 11.
5. **Plan sem mudanças no CD**: o apply do plano salvo vazio não pode falhar, e o comentário de plan no PR é atualizado em vez de empilhar um comentário por push — autoteste em Task 6 e verificação em Task 7.

---

## Estrutura de arquivos

```
.github/workflows/
  ci.yml                      CI deste repo: lint, unit, self-test, validação do PR
  release.yml                 release deste repo (tag fora da main) — já existe, passa a usar scripts/
  ci-infra-terraform.yml      reutilizável: PR → plan comentado
  cd-infra-terraform.yml      reutilizável: push/rollback → plan salvo + apply
  ci-terraform-module.yml     reutilizável: PR no repo de módulos
  pr-validation.yml           reutilizável: fluxo de branches + título
  release-semantic.yml        reutilizável: release dos consumidores (ADR-14)
  rollback-infra.yml          reutilizável: issue de rollback → cd com ref = tag
  destroy-infra.yml           reutilizável: issue de destroy → só dev
actions/
  validate-pr/                action.yml · check-branch-flow.sh · check-title.sh
  parse-config/               action.yml · parse-config.sh
  setup-terraform-aws/        action.yml
  terraform-plan/             action.yml · plan.sh
  terraform-apply/            action.yml
  replace-tokens/             action.yml · replace-tokens.py
  changed-modules/            action.yml · changed-modules.sh
  parse-issue/                action.yml · parse-issue.sh
scripts/
  next-version.sh · pin-internal-refs.sh · dev-tools.sh
tests/
  lib.sh · run.sh · *_test.sh
  fixtures/infra-basic/       consumidor de exemplo sem AWS
  fixtures/pipeline/          .pipeline.yml válidos e inválidos
docs/
  conventions.md · workflows/<nome>.md
```

---

### Task 1: Harness de testes, ferramentas locais e CI de lint

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/lib_test.sh`, `scripts/dev-tools.sh`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `tests/lib.sh` com `assert_eq <esperado> <obtido> <mensagem>`, `assert_exit <código> <mensagem> -- <comando...>`, `finish`; `tests/run.sh` roda todo `tests/*_test.sh` e sai com 1 se algum falhar; job `unit` e `lint` no `ci.yml`

- [ ] **Step 1: Instalar as ferramentas locais**

Create `scripts/dev-tools.sh`:

```bash
#!/usr/bin/env bash
# Instala em ~/.local/bin as ferramentas usadas pelos testes e pelo lint locais.
# Os runners do GitHub já têm yq, jq e shellcheck; actionlint é baixado no CI.
set -euo pipefail
BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
curl -sSfL -o "$BIN/yq" https://github.com/mikefarah/yq/releases/download/v4.53.6/yq_linux_amd64
curl -sSfL -o "$BIN/jq" https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
chmod +x "$BIN/yq" "$BIN/jq"
curl -sSfL https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz \
  | tar -xJ -C /tmp && mv /tmp/shellcheck-v0.10.0/shellcheck "$BIN/"
(cd "$BIN" && bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash) 1.7.12)
echo "Ferramentas em $BIN — garanta que ele está no PATH."
```

Run: `bash scripts/dev-tools.sh && yq --version && jq --version && shellcheck --version | head -2 && actionlint -version`
Expected: yq v4.53.6, jq-1.7.1, shellcheck 0.10.0, actionlint 1.7.12

- [ ] **Step 2: Escrever o teste do próprio harness (falha: `tests/lib.sh` não existe)**

Create `tests/lib_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "lib"
assert_eq "a" "a" "assert_eq aceita valores iguais"
assert_exit 0 "assert_exit captura sucesso" -- true
assert_exit 1 "assert_exit captura falha" -- false
out=$(bash -c 'source tests/lib.sh; assert_eq a b "x" >/dev/null; echo $FAILS')
assert_eq "1" "$out" "assert_eq conta falha"
finish
```

Run: `bash tests/lib_test.sh`
Expected: FAIL — `tests/lib.sh: No such file or directory`

- [ ] **Step 3: Implementar `tests/lib.sh` e `tests/run.sh`**

Create `tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Assertions mínimas para testes em bash. Uso: source tests/lib.sh
set -uo pipefail
FAILS=0

assert_eq() { # <esperado> <obtido> <mensagem>
  if [[ "$1" == "$2" ]]; then
    echo "  ok   $3"
  else
    echo "  FAIL $3"
    echo "       esperado: $1"
    echo "       obtido:   $2"
    FAILS=$((FAILS + 1))
  fi
}

assert_exit() { # <código> <mensagem> -- <comando...>
  local want=$1 msg=$2
  shift 3
  "$@" >/dev/null 2>&1
  assert_eq "$want" "$?" "$msg"
}

finish() {
  if [[ $FAILS -eq 0 ]]; then echo "PASS"; else echo "$FAILS falha(s)"; exit 1; fi
}
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Roda todos os tests/*_test.sh a partir da raiz do repositório.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
for t in tests/*_test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
```

- [ ] **Step 4: Rodar e ver passar**

Run: `bash tests/run.sh`
Expected: `== tests/lib_test.sh` … 4 × `ok` … `PASS`, exit 0

- [ ] **Step 5: CI deste repositório (lint + unit)**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
    branches: [dev, main]

permissions:
  contents: read

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7

      - name: actionlint
        run: |
          bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash) 1.7.12
          ./actionlint -color

      - name: shellcheck
        run: find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -r shellcheck -x

  unit:
    name: Unit tests
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - run: bash tests/run.sh
```

Run: `actionlint && find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -r shellcheck -x && bash tests/run.sh`
Expected: sem saída do actionlint e do shellcheck; testes `PASS`

- [ ] **Step 6: Commit**

```bash
git add tests scripts/dev-tools.sh .github/workflows/ci.yml
git commit -m "ci: harness de testes em bash e lint de workflows e scripts"
```

---

### Task 2: Scripts de release com testes (versão e reescrita de referências)

**Files:**
- Create: `scripts/next-version.sh`, `scripts/pin-internal-refs.sh`, `tests/next-version_test.sh`, `tests/pin-internal-refs_test.sh`
- Modify: `.github/workflows/release.yml` (substituir a lógica inline pelos scripts)

**Interfaces:**
- Produces: `scripts/next-version.sh` — sem argumentos, no diretório do repositório git; imprime `X.Y.Z` ou nada (sem commits novos); `scripts/pin-internal-refs.sh <X.Y.Z> <arquivo...>` — reescreve no lugar as referências internas de actions **e** de workflows para `@vX.Y.Z`

- [ ] **Step 1: Escrever os testes (falham: scripts não existem)**

Create `tests/next-version_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
SCRIPT="$(pwd)/scripts/next-version.sh"
echo "next-version"

repo=$(mktemp -d)
cd "$repo" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
commit() { git commit -q --allow-empty -m "$1"; }
release_detached() { # simula o release: commit fora da main + tag
  local v; v=$(bash "$SCRIPT"); [[ -z "$v" ]] && { echo ""; return; }
  git checkout -q --detach; commit "chore(release): v$v"; git tag -a "v$v" -m "v$v"; git checkout -q main; echo "v$v"
}
release_on_main() { # simula o release sem commit de reescrita: tag na própria main
  local v; v=$(bash "$SCRIPT"); git tag -a "v$v" -m "v$v"; echo "v$v"
}

commit "chore: commit inicial"
assert_eq "v1.0.0" "$(release_on_main)" "primeiro release é 1.0.0"
assert_eq "" "$(bash "$SCRIPT")" "tag na própria main: sem commit novo, sem release"
commit "docs: ajuste"
assert_eq "v1.0.1" "$(release_detached)" "docs gera patch (tag anterior na main)"
assert_eq "" "$(bash "$SCRIPT")" "tag fora da main: sem commit novo, sem release"
commit "feat: novo workflow"; commit "fix: corrige"
assert_eq "v1.1.0" "$(release_detached)" "feat gera minor"
commit "feat(ci)!: muda inputs"
assert_eq "v2.0.0" "$(release_detached)" "feat! com escopo gera major"
commit $'refactor: y\n\nBREAKING CHANGE: remove input'
assert_eq "v3.0.0" "$(release_detached)" "BREAKING CHANGE no corpo gera major"
commit "Merge pull request #9 from x/dev"
assert_eq "v3.0.1" "$(release_detached)" "merge commit gera patch"
cd / && rm -rf "$repo"
finish
```

Create `tests/pin-internal-refs_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "pin-internal-refs"
f=$(mktemp)
cat > "$f" <<'EOF'
      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@main
      - uses: "MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@v1.0.0"
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@main
      - uses: actions/checkout@v7
EOF
bash scripts/pin-internal-refs.sh 1.2.3 "$f"
assert_eq "      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@v1.2.3" "$(sed -n 1p "$f")" "action interna @main"
assert_eq '      - uses: "MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@v1.2.3"' "$(sed -n 2p "$f")" "action interna entre aspas"
assert_eq "    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@v1.2.3" "$(sed -n 3p "$f")" "workflow interno"
assert_eq "      - uses: actions/checkout@v7" "$(sed -n 4p "$f")" "action de terceiro intacta"
assert_exit 1 "versão inválida é recusada" -- bash scripts/pin-internal-refs.sh v1 "$f"
rm -f "$f"
finish
```

Run: `bash tests/run.sh`
Expected: FAIL nos dois arquivos novos (`No such file or directory`)

- [ ] **Step 2: Implementar `scripts/next-version.sh`**

```bash
#!/usr/bin/env bash
# Calcula a próxima versão semver a partir da última tag v* (ADR-14).
# A tag pode apontar para um commit da main (release sem reescrita) ou para um
# commit de release FORA da main, cujo pai é o commit da main liberado.
# Saída: X.Y.Z em stdout, ou nada se não houver commit novo desde a tag.
set -euo pipefail

last_tag=$(git tag --list 'v*' --sort=-v:refname | head -n1)
if [[ -z "$last_tag" ]]; then
  echo "1.0.0"
  exit 0
fi

if git merge-base --is-ancestor "$last_tag" HEAD; then
  base="$last_tag"
else
  base=$(git rev-parse "${last_tag}^")
fi
range="${base}..HEAD"
[[ -z "$(git rev-list "$range")" ]] && exit 0

IFS=. read -r major minor patch <<< "${last_tag#v}"
if git log --format=%B "$range" | grep -qE '^BREAKING CHANGE|^[a-z]+(\([^)]*\))?!:'; then
  echo "$((major + 1)).0.0"
elif git log --format=%s "$range" | grep -qE '^feat(\([^)]*\))?:'; then
  echo "${major}.$((minor + 1)).0"
else
  echo "${major}.${minor}.$((patch + 1))"
fi
```

- [ ] **Step 3: Implementar `scripts/pin-internal-refs.sh`**

```bash
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
```

- [ ] **Step 4: Rodar os testes**

Run: `bash tests/run.sh && shellcheck -x scripts/*.sh tests/*.sh`
Expected: todos `PASS`; shellcheck sem saída

- [ ] **Step 5: `release.yml` passa a usar os scripts**

Replace the two `run:` blocks of steps `Calculate next version` and `Tag with pinned internal references` in `.github/workflows/release.yml` by:

```yaml
      - name: Calculate next version
        id: version
        run: echo "version=$(bash scripts/next-version.sh)" >> "$GITHUB_OUTPUT"

      - name: Tag with pinned internal references
        if: steps.version.outputs.version != ''
        env:
          VERSION: ${{ steps.version.outputs.version }}
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout --detach
          bash scripts/pin-internal-refs.sh "$VERSION" .github/workflows/*.yml
          if ! git diff --quiet; then
            git commit -qam "chore(release): v${VERSION}"
          fi
          git tag -a "v${VERSION}" -m "v${VERSION}"
          git push origin "v${VERSION}"
```

Run: `actionlint .github/workflows/release.yml`
Expected: sem saída

- [ ] **Step 6: Commit**

```bash
git add scripts/next-version.sh scripts/pin-internal-refs.sh tests/next-version_test.sh tests/pin-internal-refs_test.sh .github/workflows/release.yml
git commit -m "refactor: cálculo de versão e reescrita de referências em scripts testados"
```

---

### Task 3: Validação de PR (fluxo de branches e título)

**Files:**
- Create: `actions/validate-pr/action.yml`, `actions/validate-pr/check-branch-flow.sh`, `actions/validate-pr/check-title.sh`, `tests/validate-pr_test.sh`, `.github/workflows/pr-validation.yml`
- Modify: `.github/workflows/ci.yml` (job `pr` usando a action local)

**Interfaces:**
- Produces: action `validate-pr` (sem inputs; lê `github.head_ref`, `github.base_ref`, `github.event.pull_request.title`); scripts leem `HEAD_REF`, `BASE_REF`, `PR_TITLE`; workflow reutilizável `pr-validation.yml` (sem inputs), job de nome `Validate Pull Request`

- [ ] **Step 1: Escrever os testes (falham)**

Create `tests/validate-pr_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
D=actions/validate-pr
echo "validate-pr: fluxo de branches"
flow() { HEAD_REF=$1 BASE_REF=$2 bash "$D/check-branch-flow.sh"; }
assert_exit 0 "feature/x → dev" -- flow feature/x dev
assert_exit 0 "dev → main" -- flow dev main
assert_exit 1 "fix/x → dev é recusado" -- flow fix/x dev
assert_exit 1 "feature/x → main é recusado" -- flow feature/x main
assert_exit 1 "hotfix/x → main é recusado" -- flow hotfix/x main
assert_exit 1 "qualquer → outra base é recusado" -- flow feature/x release

echo "validate-pr: título"
title() { PR_TITLE=$1 bash "$D/check-title.sh"; }
assert_exit 0 "feat simples" -- title "feat: adiciona workflow de plan"
assert_exit 0 "escopo e !" -- title "feat(github-oidc)!: remove input legado"
assert_exit 0 "ci" -- title "ci: release automático na main"
assert_exit 1 "sem tipo" -- title "adiciona workflow"
assert_exit 1 "tipo desconhecido" -- title "feature: adiciona workflow"
assert_exit 1 "descrição curta" -- title "fix: typo"
assert_exit 1 "sem espaço após dois-pontos" -- title "fix:corrige o plan"
finish
```

Run: `bash tests/validate-pr_test.sh`
Expected: FAIL (scripts inexistentes)

- [ ] **Step 2: Implementar os scripts**

Create `actions/validate-pr/check-branch-flow.sh`:

```bash
#!/usr/bin/env bash
# Regra de esteira (ADR-13): somente feature/* → dev e dev → main.
set -euo pipefail
: "${HEAD_REF:?HEAD_REF ausente}" "${BASE_REF:?BASE_REF ausente}"
case "$BASE_REF" in
  dev)
    [[ "$HEAD_REF" == feature/* ]] || { echo "::error::PR para 'dev' só a partir de 'feature/*' (origem: '$HEAD_REF')."; exit 1; } ;;
  main)
    [[ "$HEAD_REF" == "dev" ]] || { echo "::error::PR para 'main' só a partir de 'dev' (origem: '$HEAD_REF')."; exit 1; } ;;
  *)
    echo "::error::Base '$BASE_REF' fora do fluxo: PRs só para 'dev' ou 'main'."; exit 1 ;;
esac
echo "Fluxo válido: $HEAD_REF → $BASE_REF"
```

Create `actions/validate-pr/check-title.sh`:

```bash
#!/usr/bin/env bash
# Título em Conventional Commits, descrição com no mínimo 10 caracteres.
set -euo pipefail
: "${PR_TITLE:?PR_TITLE ausente}"
types='feat|fix|docs|chore|refactor|test|ci|build|perf|style|revert'
if [[ ! "$PR_TITLE" =~ ^($types)(\([a-z0-9._-]+\))?!?:\ .{10,}$ ]]; then
  echo "::error::Título fora do padrão: '<tipo>(escopo opcional)!: descrição com 10+ caracteres'. Tipos: ${types//|/, }."
  exit 1
fi
echo "Título válido."
```

- [ ] **Step 3: Rodar os testes**

Run: `bash tests/validate-pr_test.sh && shellcheck -x actions/validate-pr/*.sh`
Expected: 13 × `ok`, `PASS`; shellcheck sem saída

- [ ] **Step 4: Action e workflow reutilizável**

Create `actions/validate-pr/action.yml`:

```yaml
name: Validate PR
description: Regra de esteira (feature/* → dev → main) e título em Conventional Commits.

runs:
  using: composite
  steps:
    - name: Fluxo de branches
      shell: bash
      env:
        HEAD_REF: ${{ github.head_ref }}
        BASE_REF: ${{ github.base_ref }}
      run: bash "${{ github.action_path }}/check-branch-flow.sh"

    - name: Título
      shell: bash
      env:
        PR_TITLE: ${{ github.event.pull_request.title }}
      run: bash "${{ github.action_path }}/check-title.sh"
```

Create `.github/workflows/pr-validation.yml`:

```yaml
# Reutilizável. Chamador: on: pull_request (types: opened, edited, synchronize, reopened).
name: PR Validation

on:
  workflow_call:

permissions:
  contents: read

jobs:
  validate:
    name: Validate Pull Request
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/validate-pr@main
```

Add to `.github/workflows/ci.yml`, under `jobs:` (this repo validates its own PRs with the local action):

```yaml
  pr:
    name: Validate Pull Request
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v7
      - uses: ./actions/validate-pr
```

And add `types: [opened, edited, synchronize, reopened]` under `on.pull_request` in `ci.yml`.

Run: `actionlint`
Expected: sem saída

- [ ] **Step 5: Commit**

```bash
git add actions/validate-pr tests/validate-pr_test.sh .github/workflows/pr-validation.yml .github/workflows/ci.yml
git commit -m "feat: validação de pr com fluxo feature → dev → main e título convencional"
```

---

### Task 4: `parse-config` (contrato do `.pipeline.yml`)

**Files:**
- Create: `actions/parse-config/action.yml`, `actions/parse-config/parse-config.sh`, `tests/fixtures/pipeline/valid.yml`, `tests/fixtures/pipeline/missing-version.yml`, `tests/parse-config_test.sh`

**Interfaces:**
- Produces: action `parse-config` — inputs `environment` (obrigatório), `config-file` (padrão `.pipeline.yml`); outputs `config` (JSON plano com chaves `pipe_<seção>_<chave>`, p.ex. `pipe_infra_terraform-version`, `pipe_infra_working-path`, `pipe_environment_<chave>`), `terraform-version`, `working-path`, `files-to-replace` (lista separada por espaço). Script: `parse-config.sh <arquivo> <ambiente>` escreve `chave=valor` em `$GITHUB_OUTPUT`.

- [ ] **Step 1: Fixtures e testes (falham)**

Create `tests/fixtures/pipeline/valid.yml`:

```yaml
infra:
  terraform-version: "1.14.9"
  working-path: terraform-aws

environments:
  dev:
    note: desenvolvimento
  prod: {}
  files-to-replace:
    - terraform-aws/app.json
```

Create `tests/fixtures/pipeline/missing-version.yml`:

```yaml
infra:
  working-path: terraform-aws
environments:
  dev: {}
```

Create `tests/parse-config_test.sh`:

```bash
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
```

Run: `bash tests/parse-config_test.sh`
Expected: FAIL (script inexistente)

- [ ] **Step 2: Implementar `parse-config.sh`**

```bash
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
```

- [ ] **Step 3: Rodar os testes**

Run: `bash tests/parse-config_test.sh && shellcheck -x actions/parse-config/*.sh`
Expected: 9 × `ok`, `PASS`

- [ ] **Step 4: Action**

Create `actions/parse-config/action.yml`:

```yaml
name: Parse Config
description: Lê o .pipeline.yml do consumidor e publica a configuração do ambiente.

inputs:
  environment:
    description: Ambiente (chave em environments do .pipeline.yml)
    required: true
  config-file:
    description: Caminho do arquivo de configuração
    required: false
    default: .pipeline.yml

outputs:
  config:
    description: JSON plano com chaves pipe_<seção>_<chave>
    value: ${{ steps.parse.outputs.config }}
  terraform-version:
    description: infra.terraform-version
    value: ${{ steps.parse.outputs.terraform-version }}
  working-path:
    description: infra.working-path
    value: ${{ steps.parse.outputs.working-path }}
  files-to-replace:
    description: Arquivos para substituição de tokens, separados por espaço
    value: ${{ steps.parse.outputs.files-to-replace }}

runs:
  using: composite
  steps:
    - id: parse
      shell: bash
      run: bash "${{ github.action_path }}/parse-config.sh" "${{ inputs.config-file }}" "${{ inputs.environment }}"
```

Run: `actionlint`
Expected: sem saída

- [ ] **Step 5: Commit**

```bash
git add actions/parse-config tests/parse-config_test.sh tests/fixtures/pipeline
git commit -m "feat: parse-config com validação do ambiente e da versão do terraform"
```

---

### Task 5: `setup-terraform-aws` e autoteste no CI

**Files:**
- Create: `actions/setup-terraform-aws/action.yml`, `tests/fixtures/infra-basic/.pipeline.yml`, `tests/fixtures/infra-basic/terraform-aws/main.tf`, `tests/fixtures/infra-basic/terraform-aws/environments/dev.tfvars`
- Modify: `.github/workflows/ci.yml` (job `self-test`)

**Interfaces:**
- Consumes: `parse-config` (Task 4)
- Produces: action `setup-terraform-aws` — inputs `terraform-version` (obrigatório), `aws-role-arn` (opcional; vazio = não assume role), `aws-region` (padrão `sa-east-1`); instala o Terraform **sem wrapper**. Fixture `tests/fixtures/infra-basic` (consumidor sem AWS: só `terraform_data`)

- [ ] **Step 1: Fixture do consumidor de exemplo**

Create `tests/fixtures/infra-basic/.pipeline.yml`:

```yaml
infra:
  terraform-version: "1.14.9"
  working-path: terraform-aws

environments:
  dev: {}
```

Create `tests/fixtures/infra-basic/terraform-aws/main.tf`:

```hcl
# Consumidor de exemplo do autoteste: nenhum provider, nada na AWS.
terraform {
  required_version = ">= 1.14"
}

variable "environment" {
  type = string
}

resource "terraform_data" "marker" {
  input = "autoteste-${var.environment}"
}

output "marker" {
  value = terraform_data.marker.output
}
```

Create `tests/fixtures/infra-basic/terraform-aws/environments/dev.tfvars`:

```hcl
environment = "dev"
```

Run: `cd tests/fixtures/infra-basic/terraform-aws && terraform fmt -check && terraform init -backend=false -input=false >/dev/null && terraform validate && rm -rf .terraform .terraform.lock.hcl; cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 2: Action**

Create `actions/setup-terraform-aws/action.yml`:

```yaml
name: Setup Terraform + AWS
description: Instala o Terraform (sem wrapper) e, se houver role, assume-a via OIDC.

inputs:
  terraform-version:
    description: Versão do Terraform (vem do .pipeline.yml)
    required: true
  aws-role-arn:
    description: Role assumida via OIDC. Vazio = não configura credenciais (autoteste, módulos).
    required: false
    default: ''
  aws-region:
    description: Região AWS
    required: false
    default: sa-east-1

runs:
  using: composite
  steps:
    - uses: hashicorp/setup-terraform@v4
      with:
        terraform_version: ${{ inputs.terraform-version }}
        terraform_wrapper: false

    # O job chamador precisa de permissions: id-token: write.
    - if: inputs.aws-role-arn != ''
      uses: aws-actions/configure-aws-credentials@v6
      with:
        role-to-assume: ${{ inputs.aws-role-arn }}
        aws-region: ${{ inputs.aws-region }}
```

- [ ] **Step 3: Job `self-test` no CI (primeira parte)**

Add to `.github/workflows/ci.yml` under `jobs:`:

```yaml
  self-test:
    name: Self-test
    runs-on: ubuntu-latest
    timeout-minutes: 15
    defaults:
      run:
        working-directory: tests/fixtures/infra-basic
    steps:
      - uses: actions/checkout@v7

      - id: config
        uses: ./actions/parse-config
        with:
          environment: dev
          config-file: tests/fixtures/infra-basic/.pipeline.yml

      - uses: ./actions/setup-terraform-aws
        with:
          terraform-version: ${{ steps.config.outputs.terraform-version }}

      - name: Versão instalada é a do .pipeline.yml
        run: terraform version -json | jq -e --arg v "${{ steps.config.outputs.terraform-version }}" '.terraform_version == $v'
```

Run: `actionlint`
Expected: sem saída

- [ ] **Step 4: Commit**

```bash
git add actions/setup-terraform-aws tests/fixtures/infra-basic .github/workflows/ci.yml
git commit -m "feat: setup de terraform sem wrapper e oidc opcional, com autoteste"
```

---

### Task 6: `terraform-plan`, `terraform-apply` e `replace-tokens`

**Files:**
- Create: `actions/terraform-plan/action.yml`, `actions/terraform-plan/plan.sh`, `actions/terraform-apply/action.yml`, `actions/replace-tokens/action.yml`, `actions/replace-tokens/replace-tokens.py`, `tests/replace-tokens_test.sh`
- Modify: `.github/workflows/ci.yml` (continuação do `self-test`)

**Interfaces:**
- Consumes: `setup-terraform-aws` (Task 5)
- Produces:
  - action `terraform-plan` — inputs `working-directory`, `environment`, `backend-bucket` (vazio = `init -backend=false`), `backend-key`, `lint` (`true`/`false`, padrão `true`), `destroy` (padrão `false`); outputs `has-changes` (`true`/`false`), `plan-file` (caminho absoluto do plano salvo), `plan-text` (caminho absoluto do plano em texto)
  - `plan.sh` — lê as variáveis de ambiente `ENVIRONMENT`, `BACKEND_BUCKET`, `BACKEND_KEY`, `LINT`, `DESTROY`; roda no diretório do Terraform
  - action `terraform-apply` — inputs `working-directory`, `plan-file`
  - action `replace-tokens` — inputs `files` (separados por espaço), `config` (JSON do parse-config); substitui `${pipe_<chave>}`

- [ ] **Step 1: Teste do replace-tokens (falha)**

Create `tests/replace-tokens_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "replace-tokens"
d=$(mktemp -d)
printf '{"role": "${pipe_environment_role-arn}", "keep": "${other}"}\n' > "$d/a.json"
CONFIG='{"pipe_environment_role-arn":"arn:aws:iam::1:role/x"}' FILES="$d/a.json" python3 actions/replace-tokens/replace-tokens.py
assert_eq '{"role": "arn:aws:iam::1:role/x", "keep": "${other}"}' "$(cat "$d/a.json")" "token conhecido substituído, desconhecido intacto"
assert_exit 0 "lista vazia é no-op" -- env CONFIG='{}' FILES='' python3 actions/replace-tokens/replace-tokens.py
assert_exit 1 "arquivo listado inexistente falha" -- env CONFIG='{}' FILES="$d/nao-existe" python3 actions/replace-tokens/replace-tokens.py
rm -rf "$d"
finish
```

Run: `bash tests/replace-tokens_test.sh`
Expected: FAIL (script inexistente)

- [ ] **Step 2: Implementar `replace-tokens.py` e a action**

Create `actions/replace-tokens/replace-tokens.py`:

```python
"""Substitui ${pipe_<chave>} nos arquivos listados pelos valores do parse-config.

Variáveis: FILES (separados por espaço), CONFIG (JSON plano do parse-config).
Tokens sem valor conhecido ficam como estão.
"""
import json
import os
import re
import sys

config = json.loads(os.environ.get("CONFIG") or "{}")
files = (os.environ.get("FILES") or "").split()
token = re.compile(r"\$\{(pipe_[A-Za-z0-9_.-]+)\}")

for path in files:
    if not os.path.isfile(path):
        print(f"::error::arquivo para substituição não encontrado: {path}")
        sys.exit(1)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = token.sub(lambda m: str(config[m.group(1)]) if m.group(1) in config else m.group(0), text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"tokens substituídos em {path}")
```

Create `actions/replace-tokens/action.yml`:

```yaml
name: Replace Tokens
description: Substitui ${pipe_<chave>} nos arquivos do files-to-replace do .pipeline.yml.

inputs:
  files:
    description: Arquivos separados por espaço (vazio = nada a fazer)
    required: false
    default: ''
  config:
    description: JSON do output config do parse-config
    required: true

runs:
  using: composite
  steps:
    - shell: bash
      env:
        FILES: ${{ inputs.files }}
        CONFIG: ${{ inputs.config }}
      run: python3 "${{ github.action_path }}/replace-tokens.py"
```

Run: `bash tests/replace-tokens_test.sh`
Expected: 3 × `ok`, `PASS`

- [ ] **Step 3: Implementar `plan.sh` e a action `terraform-plan`**

Create `actions/terraform-plan/plan.sh`:

```bash
#!/usr/bin/env bash
# fmt → init → validate → (tflint, checkov) → plan salvo. Roda no diretório do Terraform.
# Variáveis: ENVIRONMENT, BACKEND_BUCKET (vazio = sem backend), BACKEND_KEY, LINT, DESTROY.
set -euo pipefail
: "${ENVIRONMENT:?}" "${LINT:=true}" "${DESTROY:=false}"
var_file="environments/${ENVIRONMENT}.tfvars"
[[ -f "$var_file" ]] || { echo "::error::$var_file não encontrado."; exit 1; }

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
```

Create `actions/terraform-plan/action.yml`:

```yaml
name: Terraform Plan
description: fmt, init, validate, lint (tflint + checkov em relatório) e plan salvo em arquivo.

inputs:
  working-directory:
    description: Diretório do Terraform (infra.working-path)
    required: true
  environment:
    description: Ambiente — usa environments/<ambiente>.tfvars
    required: true
  backend-bucket:
    description: Bucket de state. Vazio = init -backend=false (autoteste)
    required: false
    default: ''
  backend-key:
    description: Chave do state — <repositório>/terraform.tfstate, sem pasta de ambiente
    required: false
    default: ''
  lint:
    description: Roda tflint e checkov (true/false)
    required: false
    default: 'true'
  destroy:
    description: Plano de destruição (true/false)
    required: false
    default: 'false'

outputs:
  has-changes:
    description: true se o plano tem mudanças
    value: ${{ steps.plan.outputs.has-changes }}
  plan-file:
    description: Caminho absoluto do plano salvo
    value: ${{ steps.plan.outputs.plan-file }}
  plan-text:
    description: Caminho absoluto do plano em texto
    value: ${{ steps.plan.outputs.plan-text }}

runs:
  using: composite
  steps:
    - id: plan
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        ENVIRONMENT: ${{ inputs.environment }}
        BACKEND_BUCKET: ${{ inputs.backend-bucket }}
        BACKEND_KEY: ${{ inputs.backend-key }}
        LINT: ${{ inputs.lint }}
        DESTROY: ${{ inputs.destroy }}
      run: bash "${{ github.action_path }}/plan.sh"
```

- [ ] **Step 4: Action `terraform-apply`**

Create `actions/terraform-apply/action.yml`:

```yaml
name: Terraform Apply
description: Aplica o plano salvo pelo terraform-plan (nunca -auto-approve sobre um plano novo).

inputs:
  working-directory:
    description: Diretório do Terraform
    required: true
  plan-file:
    description: Caminho do plano salvo (output plan-file do terraform-plan)
    required: true

runs:
  using: composite
  steps:
    - shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PLAN_FILE: ${{ inputs.plan-file }}
      run: terraform apply -input=false -lock-timeout=5m -no-color "$PLAN_FILE"
```

- [ ] **Step 5: Autoteste completo (plan com mudança, apply, plan sem mudança)**

Append to the `self-test` job steps in `.github/workflows/ci.yml`:

```yaml
      - uses: ./actions/replace-tokens
        with:
          files: ${{ steps.config.outputs.files-to-replace }}
          config: ${{ steps.config.outputs.config }}

      - id: plan
        uses: ./actions/terraform-plan
        with:
          working-directory: tests/fixtures/infra-basic/terraform-aws
          environment: dev

      - name: Primeiro plano tem mudanças
        run: test "${{ steps.plan.outputs.has-changes }}" = "true"

      - uses: ./actions/terraform-apply
        with:
          working-directory: tests/fixtures/infra-basic/terraform-aws
          plan-file: ${{ steps.plan.outputs.plan-file }}

      - id: replan
        uses: ./actions/terraform-plan
        with:
          working-directory: tests/fixtures/infra-basic/terraform-aws
          environment: dev
          lint: 'false'

      - name: Depois do apply não há mudanças
        run: test "${{ steps.replan.outputs.has-changes }}" = "false"

      - name: Apply de plano vazio não falha
        uses: ./actions/terraform-apply
        with:
          working-directory: tests/fixtures/infra-basic/terraform-aws
          plan-file: ${{ steps.replan.outputs.plan-file }}
```

Run locally (simula o job, sem tflint/checkov): `cd tests/fixtures/infra-basic/terraform-aws && GITHUB_OUTPUT=/tmp/o ENVIRONMENT=dev LINT=false bash ../../../../actions/terraform-plan/plan.sh && grep has-changes /tmp/o && terraform apply -input=false tfplan >/dev/null && : > /tmp/o && GITHUB_OUTPUT=/tmp/o ENVIRONMENT=dev LINT=false bash ../../../../actions/terraform-plan/plan.sh && grep has-changes /tmp/o; rm -rf .terraform* tfplan tfplan.txt terraform.tfstate*; cd -`
Expected: `has-changes=true`, depois `has-changes=false`

Run: `actionlint && shellcheck -x actions/*/*.sh && bash tests/run.sh`
Expected: sem saída dos linters; testes `PASS`

- [ ] **Step 6: Commit**

```bash
git add actions/terraform-plan actions/terraform-apply actions/replace-tokens tests/replace-tokens_test.sh .github/workflows/ci.yml
git commit -m "feat: plan salvo com lint, apply do plano salvo e substituição de tokens"
```

---

### Task 7: Workflow reutilizável `ci-infra-terraform.yml`

**Files:**
- Create: `.github/workflows/ci-infra-terraform.yml`

**Interfaces:**
- Consumes: `parse-config`, `setup-terraform-aws`, `terraform-plan` (Tasks 4–6)
- Produces: workflow `ci-infra-terraform.yml` — input `environment` (obrigatório); job `Validate Infrastructure`; comenta o plano no PR (um comentário por ambiente, atualizado a cada push, marcador `<!-- terraform-plan:<ambiente> -->`)

- [ ] **Step 1: Escrever o workflow**

```yaml
# Reutilizável. Chamador: on: pull_request para dev (environment: dev) e para main (environment: prod).
name: Infra Terraform CI

on:
  workflow_call:
    inputs:
      environment:
        description: GitHub Environment e tfvars (dev ou prod)
        type: string
        required: true

permissions:
  contents: read

jobs:
  plan:
    name: Validate Infrastructure
    runs-on: ubuntu-latest
    timeout-minutes: 20
    environment: ${{ inputs.environment }}
    permissions:
      contents: read
      id-token: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v7

      - id: config
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@main
        with:
          environment: ${{ inputs.environment }}

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@main
        with:
          terraform-version: ${{ steps.config.outputs.terraform-version }}
          aws-role-arn: ${{ vars.AWS_ROLE_ARN }}

      - id: plan
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/terraform-plan@main
        with:
          working-directory: ${{ steps.config.outputs.working-path }}
          environment: ${{ inputs.environment }}
          backend-bucket: ${{ vars.TF_STATE_BUCKET }}
          backend-key: ${{ github.event.repository.name }}/terraform.tfstate

      - name: Comentar o plano no PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v9
        env:
          PLAN_TEXT: ${{ steps.plan.outputs.plan-text }}
          ENVIRONMENT: ${{ inputs.environment }}
        with:
          script: |
            const fs = require('fs');
            const marker = `<!-- terraform-plan:${process.env.ENVIRONMENT} -->`;
            let text = fs.readFileSync(process.env.PLAN_TEXT, 'utf8');
            const limit = 60000;
            if (text.length > limit) text = text.slice(0, limit) + '\n… (truncado — plano completo no log do job)';
            const summary = (text.match(/^(Plan:.*|No changes.*)$/m) || ['sem resumo'])[0];
            const body = `${marker}\n### Terraform plan — \`${process.env.ENVIRONMENT}\`\n**${summary}**\n\n<details><summary>Plano completo</summary>\n\n\`\`\`\n${text}\n\`\`\`\n</details>`;
            const { owner, repo } = context.repo;
            const issue_number = context.issue.number;
            const comments = await github.paginate(github.rest.issues.listComments, { owner, repo, issue_number });
            const mine = comments.find(c => c.body && c.body.startsWith(marker));
            if (mine) await github.rest.issues.updateComment({ owner, repo, comment_id: mine.id, body });
            else await github.rest.issues.createComment({ owner, repo, issue_number, body });
```

- [ ] **Step 2: Lint**

Run: `actionlint .github/workflows/ci-infra-terraform.yml`
Expected: sem saída

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci-infra-terraform.yml
git commit -m "feat: workflow reutilizável de ci de infra com plano comentado no pr"
```

(Verificação real: primeiro PR de um consumidor após o release — Task 13, Step 6.)

---

### Task 8: Workflow reutilizável `cd-infra-terraform.yml`

**Files:**
- Create: `.github/workflows/cd-infra-terraform.yml`

**Interfaces:**
- Consumes: `parse-config`, `replace-tokens`, `setup-terraform-aws`, `terraform-plan`, `terraform-apply`
- Produces: workflow `cd-infra-terraform.yml` — inputs `environment` (obrigatório), `ref` (opcional; tag para rollback); job `Deploy Infrastructure`; concorrência `<repositório>-<ambiente>` sem cancelamento

- [ ] **Step 1: Escrever o workflow**

```yaml
# Reutilizável. Chamador: on: push em dev (environment: dev) e main (environment: prod); também o rollback.
name: Infra Terraform CD

on:
  workflow_call:
    inputs:
      environment:
        description: GitHub Environment e tfvars (dev ou prod)
        type: string
        required: true
      ref:
        description: Ref a aplicar (tag para rollback). Vazio = commit do evento.
        type: string
        required: false
        default: ''

permissions:
  contents: read

concurrency:
  group: ${{ github.repository }}-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy Infrastructure
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: ${{ inputs.environment }}
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ inputs.ref }}

      - id: config
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@main
        with:
          environment: ${{ inputs.environment }}

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/replace-tokens@main
        with:
          files: ${{ steps.config.outputs.files-to-replace }}
          config: ${{ steps.config.outputs.config }}

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@main
        with:
          terraform-version: ${{ steps.config.outputs.terraform-version }}
          aws-role-arn: ${{ vars.AWS_ROLE_ARN }}

      - id: plan
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/terraform-plan@main
        with:
          working-directory: ${{ steps.config.outputs.working-path }}
          environment: ${{ inputs.environment }}
          backend-bucket: ${{ vars.TF_STATE_BUCKET }}
          backend-key: ${{ github.event.repository.name }}/terraform.tfstate
          lint: 'false'

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/terraform-apply@main
        with:
          working-directory: ${{ steps.config.outputs.working-path }}
          plan-file: ${{ steps.plan.outputs.plan-file }}
```

- [ ] **Step 2: Lint e commit**

Run: `actionlint .github/workflows/cd-infra-terraform.yml`
Expected: sem saída

```bash
git add .github/workflows/cd-infra-terraform.yml
git commit -m "feat: workflow reutilizável de cd de infra com plano salvo e concorrência por ambiente"
```

---

### Task 9: `ci-terraform-module.yml` (repositório de módulos)

**Files:**
- Create: `actions/changed-modules/action.yml`, `actions/changed-modules/changed-modules.sh`, `tests/changed-modules_test.sh`, `.github/workflows/ci-terraform-module.yml`

**Interfaces:**
- Produces: `changed-modules.sh <base-ref> <head-ref>` imprime, um por linha, os nomes em `modules/<nome>` alterados (mudança em `examples/<nome>/**` conta para o módulo `<nome>`; mudança em `.github/**` ou em arquivo da raiz conta para **todos**); action `changed-modules` — inputs `base`, `head`; output `modules` (JSON array); workflow `ci-terraform-module.yml` — input `terraform-version` (padrão `1.14.9`); job `Validate Modules`

- [ ] **Step 1: Teste (falha)**

Create `tests/changed-modules_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
SCRIPT="$(pwd)/actions/changed-modules/changed-modules.sh"
echo "changed-modules"
repo=$(mktemp -d); cd "$repo" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
mkdir -p modules/a modules/b examples/b .github && touch modules/a/main.tf modules/b/main.tf README.md
git add -A && git commit -qm init && base=$(git rev-parse HEAD)
echo x >> modules/a/main.tf && git commit -qam a
assert_eq "a" "$(bash "$SCRIPT" "$base" HEAD)" "mudança em modules/a"
b2=$(git rev-parse HEAD); echo x > examples/b/main.tf && git add -A && git commit -qm b
assert_eq "b" "$(bash "$SCRIPT" "$b2" HEAD)" "mudança em examples/b conta para o módulo b"
b3=$(git rev-parse HEAD); echo x >> README.md && git commit -qam readme
assert_eq "" "$(bash "$SCRIPT" "$b3" HEAD)" "só README não valida módulo"
b4=$(git rev-parse HEAD); echo x > .github/ci.yml && git add -A && git commit -qm ci
assert_eq $'a\nb' "$(bash "$SCRIPT" "$b4" HEAD)" "mudança em .github valida todos"
cd / && rm -rf "$repo"
finish
```

Run: `bash tests/changed-modules_test.sh`
Expected: FAIL

- [ ] **Step 2: Implementar script e action**

Create `actions/changed-modules/changed-modules.sh`:

```bash
#!/usr/bin/env bash
# Lista os módulos (modules/<nome>) afetados entre dois refs.
set -euo pipefail
base="$1"; head="$2"
changed=$(git diff --name-only "$base" "$head")
if grep -qE '^\.github/' <<< "$changed"; then
  find modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  exit 0
fi
# "|| true": sem arquivo em modules/ ou examples/, o grep sai com 1 e o pipefail derrubaria o script.
{ grep -oE '^(modules|examples)/[^/]+' <<< "$changed" || true; } | cut -d/ -f2 | sort -u | while read -r m; do
  [[ -d "modules/$m" ]] && echo "$m"
done
exit 0
```

Create `actions/changed-modules/action.yml`:

```yaml
name: Changed Modules
description: Lista, em JSON, os módulos Terraform afetados entre dois refs.

inputs:
  base:
    description: Ref base
    required: true
  head:
    description: Ref head
    required: true

outputs:
  modules:
    description: JSON array com os nomes dos módulos
    value: ${{ steps.list.outputs.modules }}

runs:
  using: composite
  steps:
    - id: list
      shell: bash
      run: |
        mods=$(bash "${{ github.action_path }}/changed-modules.sh" "${{ inputs.base }}" "${{ inputs.head }}" | jq -Rsc 'split("\n") | map(select(length > 0))')
        echo "modules=$mods" >> "$GITHUB_OUTPUT"
        echo "Módulos afetados: $mods"
```

Run: `bash tests/changed-modules_test.sh && shellcheck -x actions/changed-modules/*.sh`
Expected: 4 × `ok`, `PASS`

- [ ] **Step 3: Workflow reutilizável**

Create `.github/workflows/ci-terraform-module.yml`:

```yaml
# Reutilizável. Chamador: on: pull_request no shd-terraform-aws-modules.
name: Terraform Module CI

on:
  workflow_call:
    inputs:
      terraform-version:
        description: Versão do Terraform
        type: string
        required: false
        default: '1.14.9'

permissions:
  contents: read

jobs:
  validate:
    name: Validate Modules
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - id: changed
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/changed-modules@main
        with:
          base: ${{ github.event.pull_request.base.sha }}
          head: ${{ github.event.pull_request.head.sha }}

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@main
        with:
          terraform-version: ${{ inputs.terraform-version }}

      - name: fmt, validate, tflint, checkov e terraform test
        env:
          MODULES: ${{ steps.changed.outputs.modules }}
        run: |
          set -euo pipefail
          terraform fmt -check -recursive
          curl -sSfL https://raw.githubusercontent.com/terraform-linters/tflint/v0.64.0/install_linux.sh | TFLINT_VERSION=v0.64.0 bash >/dev/null
          for m in $(jq -r '.[]' <<< "$MODULES"); do
            echo "::group::módulo $m"
            (cd "modules/$m" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color && tflint --init >/dev/null && tflint --format compact && terraform test -no-color)
            if [[ -d "examples/$m" ]]; then
              (cd "examples/$m" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color)
            fi
            pipx run checkov==3.3.19 -d "modules/$m" --framework terraform --quiet --compact --soft-fail
            echo "::endgroup::"
          done
          [[ "$MODULES" == "[]" ]] && echo "Nenhum módulo alterado."
          exit 0
```

Run: `actionlint .github/workflows/ci-terraform-module.yml`
Expected: sem saída

- [ ] **Step 4: Commit**

```bash
git add actions/changed-modules tests/changed-modules_test.sh .github/workflows/ci-terraform-module.yml
git commit -m "feat: ci reutilizável de módulos terraform só nos módulos alterados"
```

---

### Task 10: `release-semantic.yml` (release dos consumidores)

**Files:**
- Create: `.github/workflows/release-semantic.yml`

**Interfaces:**
- Produces: workflow `release-semantic.yml` (sem inputs); job `Tag and Release`; grava o `.releaserc.json` canônico no workspace do runner antes de rodar — os consumidores não precisam manter cópia

- [ ] **Step 1: Escrever o workflow**

```yaml
# Reutilizável. Chamador: on: push em main — todos os repositórios (ADR-14).
name: Semantic Release

on:
  workflow_call:

permissions:
  contents: read

jobs:
  release:
    name: Tag and Release
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - uses: actions/setup-node@v7
        with:
          node-version: lts/*

      # Regras únicas para todos os consumidores: qualquer tipo de commit gera versão.
      - name: Configuração canônica do semantic-release
        run: |
          cat > .releaserc.json <<'EOF'
          {
            "branches": ["main"],
            "tagFormat": "v${version}",
            "plugins": [
              ["@semantic-release/commit-analyzer", {
                "preset": "angular",
                "releaseRules": [
                  {"breaking": true, "release": "major"},
                  {"type": "feat", "release": "minor"},
                  {"type": "fix", "release": "patch"},
                  {"type": "perf", "release": "patch"},
                  {"type": "refactor", "release": "patch"},
                  {"type": "docs", "release": "patch"},
                  {"type": "chore", "release": "patch"},
                  {"type": "test", "release": "patch"},
                  {"type": "ci", "release": "patch"},
                  {"type": "build", "release": "patch"},
                  {"type": "style", "release": "patch"},
                  {"type": "revert", "release": "patch"}
                ]
              }],
              "@semantic-release/release-notes-generator",
              "@semantic-release/github"
            ]
          }
          EOF

      - name: semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx --yes semantic-release@24
```

- [ ] **Step 2: Lint e commit**

Run: `actionlint .github/workflows/release-semantic.yml`
Expected: sem saída

```bash
git add .github/workflows/release-semantic.yml
git commit -m "feat: release reutilizável com regras canônicas do adr-14"
```

---

### Task 11: Rollback e destroy por issue

**Files:**
- Create: `actions/parse-issue/action.yml`, `actions/parse-issue/parse-issue.sh`, `tests/parse-issue_test.sh`, `.github/workflows/rollback-infra.yml`, `.github/workflows/destroy-infra.yml`

**Interfaces:**
- Consumes: `cd-infra-terraform.yml` (Task 8), actions da Task 6
- Produces: `parse-issue.sh "<título do campo>"` lê `ISSUE_BODY` e imprime o valor do campo (primeira linha não vazia após `### <título>`, sem `\r` e espaços nas pontas); action `parse-issue` — input `field`; output `value`; workflows `rollback-infra.yml` e `destroy-infra.yml` (sem inputs; leem `github.event.issue` do chamador)

- [ ] **Step 1: Teste (falha)**

Create `tests/parse-issue_test.sh`:

```bash
#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
S=actions/parse-issue/parse-issue.sh
echo "parse-issue"
body=$'### Ambiente\r\n\r\nprod\r\n\r\n### Tag ou Release alvo\r\n\r\n  v1.2.3  \r\n\r\n### Confirmação\r\n\r\naws-megamix-infra\r\n'
assert_eq "prod" "$(ISSUE_BODY=$body bash "$S" "Ambiente")" "campo com CRLF"
assert_eq "v1.2.3" "$(ISSUE_BODY=$body bash "$S" "Tag ou Release alvo")" "espaços nas pontas removidos"
assert_eq "aws-megamix-infra" "$(ISSUE_BODY=$body bash "$S" "Confirmação")" "campo com acento"
assert_exit 1 "campo ausente falha" -- env ISSUE_BODY="$body" bash "$S" "Motivo"
assert_exit 1 "campo com '_No response_' falha" -- env ISSUE_BODY=$'### Motivo\n\n_No response_\n' bash "$S" "Motivo"
finish
```

Run: `bash tests/parse-issue_test.sh`
Expected: FAIL

- [ ] **Step 2: Implementar script e action**

Create `actions/parse-issue/parse-issue.sh`:

```bash
#!/usr/bin/env bash
# Extrai o valor de um campo de issue form ("### <título>" seguido do valor).
set -euo pipefail
field="$1"
: "${ISSUE_BODY:?ISSUE_BODY ausente}"
value=$(printf '%s\n' "$ISSUE_BODY" | tr -d '\r' | awk -v f="### ${field}" '
  $0 == f { found = 1; next }
  found && /^### / { exit }
  found && NF { gsub(/^[ \t]+|[ \t]+$/, ""); print; exit }')
if [[ -z "$value" || "$value" == "_No response_" ]]; then
  echo "::error::campo '${field}' ausente ou vazio na issue." >&2
  exit 1
fi
echo "$value"
```

Create `actions/parse-issue/action.yml`:

```yaml
name: Parse Issue Field
description: Lê um campo de issue form da issue do evento.

inputs:
  field:
    description: Título do campo (texto após "### ")
    required: true

outputs:
  value:
    description: Valor do campo
    value: ${{ steps.parse.outputs.value }}

runs:
  using: composite
  steps:
    - id: parse
      shell: bash
      env:
        ISSUE_BODY: ${{ github.event.issue.body }}
      run: echo "value=$(bash "${{ github.action_path }}/parse-issue.sh" "${{ inputs.field }}")" >> "$GITHUB_OUTPUT"
```

Run: `bash tests/parse-issue_test.sh && shellcheck -x actions/parse-issue/*.sh`
Expected: 5 × `ok`, `PASS`

- [ ] **Step 3: `rollback-infra.yml`**

```yaml
# Reutilizável. Chamador: on: issues (types: labeled) com o template de rollback.
name: Rollback Infra

on:
  workflow_call:

permissions:
  contents: read

jobs:
  parse:
    name: Parse Issue
    if: github.event.label.name == 'rollback-approved'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      environment: ${{ steps.env.outputs.value }}
      tag: ${{ steps.tag.outputs.value }}
    steps:
      - id: env
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-issue@main
        with:
          field: Ambiente
      - id: tag
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-issue@main
        with:
          field: Tag ou Release alvo
      - name: Ambiente e tag válidos
        env:
          ENVIRONMENT: ${{ steps.env.outputs.value }}
          TAG: ${{ steps.tag.outputs.value }}
          GH_TOKEN: ${{ github.token }}
        run: |
          [[ "$ENVIRONMENT" =~ ^(dev|prod)$ ]] || { echo "::error::ambiente inválido: $ENVIRONMENT"; exit 1; }
          [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::tag inválida: $TAG"; exit 1; }
          gh api "repos/${{ github.repository }}/git/ref/tags/$TAG" >/dev/null || { echo "::error::tag $TAG não existe"; exit 1; }

  rollback:
    name: Rollback
    needs: parse
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@main
    with:
      environment: ${{ needs.parse.outputs.environment }}
      ref: ${{ needs.parse.outputs.tag }}
    permissions:
      contents: read
      id-token: write

  report:
    name: Comment on Issue
    needs: [parse, rollback]
    if: always() && needs.parse.result == 'success'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v9
        env:
          RESULT: ${{ needs.rollback.result }}
          ENVIRONMENT: ${{ needs.parse.outputs.environment }}
          TAG: ${{ needs.parse.outputs.tag }}
        with:
          script: |
            const ok = process.env.RESULT === 'success';
            const run = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            await github.rest.issues.createComment({ ...context.repo, issue_number: context.issue.number,
              body: `${ok ? '✅ Rollback aplicado' : '❌ Rollback falhou'} em \`${process.env.ENVIRONMENT}\` com a tag \`${process.env.TAG}\`.\n${run}` });
```

- [ ] **Step 4: `destroy-infra.yml` (só dev, confirmação com o nome do repositório)**

```yaml
# Reutilizável. Chamador: on: issues (types: labeled) com o template de destroy.
name: Destroy Infra

on:
  workflow_call:

permissions:
  contents: read

jobs:
  destroy:
    name: Destroy (dev)
    if: github.event.label.name == 'destroy-approved'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: dev
    concurrency:
      group: ${{ github.repository }}-dev
      cancel-in-progress: false
    permissions:
      contents: read
      id-token: write
      issues: write
    steps:
      - id: env
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-issue@main
        with:
          field: Ambiente
      - id: confirm
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-issue@main
        with:
          field: Confirmação
      - name: Só dev, confirmação com o nome do repositório
        env:
          ENVIRONMENT: ${{ steps.env.outputs.value }}
          CONFIRM: ${{ steps.confirm.outputs.value }}
          REPO: ${{ github.event.repository.name }}
        run: |
          [[ "$ENVIRONMENT" == "dev" ]] || { echo "::error::destroy só é permitido em dev."; exit 1; }
          [[ "$CONFIRM" == "$REPO" ]] || { echo "::error::a confirmação deve ser exatamente '$REPO'."; exit 1; }

      - uses: actions/checkout@v7

      - id: config
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@main
        with:
          environment: dev

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@main
        with:
          terraform-version: ${{ steps.config.outputs.terraform-version }}
          aws-role-arn: ${{ vars.AWS_ROLE_ARN }}

      - id: plan
        uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/terraform-plan@main
        with:
          working-directory: ${{ steps.config.outputs.working-path }}
          environment: dev
          backend-bucket: ${{ vars.TF_STATE_BUCKET }}
          backend-key: ${{ github.event.repository.name }}/terraform.tfstate
          lint: 'false'
          destroy: 'true'

      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/terraform-apply@main
        with:
          working-directory: ${{ steps.config.outputs.working-path }}
          plan-file: ${{ steps.plan.outputs.plan-file }}

      - if: always()
        uses: actions/github-script@v9
        env:
          STATUS: ${{ job.status }}
        with:
          script: |
            const ok = process.env.STATUS === 'success';
            const run = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            await github.rest.issues.createComment({ ...context.repo, issue_number: context.issue.number,
              body: `${ok ? '✅ Destroy de dev concluído' : '❌ Destroy falhou'}.\n${run}` });
            if (ok) await github.rest.issues.update({ ...context.repo, issue_number: context.issue.number, state: 'closed' });
```

- [ ] **Step 5: Lint, testes e commit**

Run: `actionlint && bash tests/run.sh`
Expected: sem saída do actionlint; todos `PASS`

```bash
git add actions/parse-issue tests/parse-issue_test.sh .github/workflows/rollback-infra.yml .github/workflows/destroy-infra.yml
git commit -m "feat: rollback e destroy de infra por issue com validação de ambiente e tag"
```

---

### Task 12: Documentação e alinhamento da spec

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/shd-github-actions-workflows-design.md`
- Create: `docs/conventions.md`, `docs/workflows/ci-infra-terraform.md`, `docs/workflows/cd-infra-terraform.md`, `docs/workflows/ci-terraform-module.md`, `docs/workflows/pr-validation.md`, `docs/workflows/release-semantic.md`, `docs/workflows/rollback-infra.md`, `docs/workflows/destroy-infra.md`

- [ ] **Step 1: README com o catálogo e chamadores prontos**

Replace `README.md` with:

````markdown
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
````

- [ ] **Step 2: `docs/conventions.md`**

```markdown
# Convenções do consumidor

## `.pipeline.yml` (raiz do repositório)

| Chave | Obrigatória | Uso |
| --- | --- | --- |
| `infra.terraform-version` | sim | versão instalada pelo `setup-terraform-aws` |
| `infra.working-path` | sim | diretório do Terraform |
| `environments.<ambiente>` | sim, um por ambiente | valores do ambiente, expostos como `pipe_environment_<chave>` |
| `environments.files-to-replace` | não | arquivos com tokens `${pipe_<chave>}` substituídos no CD |

Ambiente não declarado ou `terraform-version` ausente **falham** o job.

## GitHub Environments `dev` e `prod`

**Variables** (não secrets): `AWS_ROLE_ARN` e `TF_STATE_BUCKET`. O job declara `environment: <ambiente>` para lê-las.

## State

Bucket `TF_STATE_BUCKET` (um por conta), chave `<repositório>/terraform.tfstate`. **Nunca** uma pasta de ambiente na chave: o bucket já é do ambiente.

## OIDC

A role precisa confiar em `repo:MegaMixDistribuidora/<repositório>:environment:<ambiente>`. O job chamador declara `permissions: id-token: write`.

## Terraform

`environments/<ambiente>.tfvars` dentro do `working-path`. O CD aplica **o plano salvo** no mesmo job — nunca um `apply -auto-approve` sobre um plano novo.

## Plano Free

Repositórios privados não têm required reviewers nem rulesets no plano Free. A proteção de prod é o merge em `main` ser feito pelo usuário (regra 6 de `git.md`) e o hook `guard-git`.
```

- [ ] **Step 3: Uma página por workflow em `docs/workflows/`**

Create each file with this structure, filling from Tasks 3 and 7–11 (inputs, jobs, permissões do chamador):

`docs/workflows/ci-infra-terraform.md`:

```markdown
# ci-infra-terraform.yml

Plan de infra em PR, com lint (tflint; checkov em relatório) e comentário no PR (um por ambiente, atualizado a cada push).

| Input | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `environment` | string | sim | `dev` ou `prod` — GitHub Environment e `environments/<ambiente>.tfvars` |

Permissões do job chamador: `contents: read`, `id-token: write`, `pull-requests: write`. Job: `Validate Infrastructure`.
```

`docs/workflows/cd-infra-terraform.md`:

```markdown
# cd-infra-terraform.yml

Plan salvo e apply do mesmo plano. Concorrência `<repositório>-<ambiente>`, sem cancelar apply em andamento.

| Input | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `environment` | string | sim | `dev` ou `prod` |
| `ref` | string | não | tag a reaplicar (rollback); vazio = commit do evento |

Permissões do job chamador: `contents: read`, `id-token: write`. Job: `Deploy Infrastructure`.
```

`docs/workflows/ci-terraform-module.md`:

```markdown
# ci-terraform-module.yml

Valida só os módulos alterados no PR (`modules/<nome>` ou `examples/<nome>`; mudança em `.github/` valida todos): `fmt`, `validate`, `tflint`, `terraform test`, `validate` do exemplo e checkov em relatório.

| Input | Tipo | Obrigatório | Padrão |
| --- | --- | --- | --- |
| `terraform-version` | string | não | `1.14.9` |

Permissões do job chamador: `contents: read`. Job: `Validate Modules`.
```

`docs/workflows/pr-validation.md`:

```markdown
# pr-validation.yml

Recusa PR fora do fluxo (`feature/*` → `dev`, `dev` → `main`) e título fora de Conventional Commits (descrição com 10+ caracteres). Sem inputs. Chamador com `types: [opened, edited, synchronize, reopened]`. Job: `Validate Pull Request`.
```

`docs/workflows/release-semantic.md`:

```markdown
# release-semantic.yml

Todo push na `main` gera tag `vX.Y.Z` e GitHub Release (ADR-14): `feat` → minor, breaking → major, qualquer outro tipo → patch. A configuração do semantic-release é gravada pelo próprio workflow — o consumidor não mantém `.releaserc.json`. Nunca commita na `main`.

Permissões do job chamador: `contents: write`, `issues: write`, `pull-requests: write`. Job: `Tag and Release`.
```

`docs/workflows/rollback-infra.md`:

```markdown
# rollback-infra.yml

Com a label `rollback-approved` numa issue do template de rollback: lê **Ambiente** e **Tag ou Release alvo**, confere que a tag existe e chama o `cd-infra-terraform.yml` com `ref` = tag. Comenta o resultado na issue.

Chamador: `on: issues (types: labeled)`; permissões `contents: read`, `id-token: write`, `issues: write`.
```

`docs/workflows/destroy-infra.md`:

```markdown
# destroy-infra.yml

Com a label `destroy-approved`: **somente dev**, e o campo **Confirmação** deve ser exatamente o nome do repositório. `plan -destroy` salvo e apply do plano. Comenta e fecha a issue em caso de sucesso.

Chamador: `on: issues (types: labeled)`; permissões `contents: read`, `id-token: write`, `issues: write`.
```

- [ ] **Step 4: Alinhar a spec ao que foi implementado**

Edit `docs/superpowers/specs/shd-github-actions-workflows-design.md`:
- §2, linha "Prod exige aprovação": trocar o motivo por `No plano Free, repositórios privados não têm required reviewers; a proteção de prod é o merge em main feito pelo usuário (regra 6 de git.md) e o hook guard-git`
- §2, linha "Actions de terceiros…": acrescentar `(checkout@v7, configure-aws-credentials@v6, setup-terraform@v4, github-script@v9, setup-node@v7)`
- §5.1, linha do `ci-infra-terraform.yml`: trocar `checkov (falha em severidade alta)` por `checkov em relatório (--soft-fail; sem chave de API não há severidade)`
- §5.1, linha do `release.yml`: renomear para `release-semantic.yml` e acrescentar `grava a configuração canônica; o consumidor não mantém .releaserc.json`
- §5.1, tabela de actions: acrescentar `changed-modules` (ci-terraform-module) e `parse-issue` (rollback e destroy)

Run: `grep -n 'severidade alta\|| `release.yml`' docs/superpowers/specs/shd-github-actions-workflows-design.md`
Expected: nenhuma linha

- [ ] **Step 5: Commit**

```bash
git add README.md docs/conventions.md docs/workflows docs/superpowers/specs/shd-github-actions-workflows-design.md
git commit -m "docs: catálogo, convenções do consumidor e spec alinhada à implementação"
```

---

### Task 13: Publicar, verificar a tag e proteger as branches

**Files:** nenhum arquivo novo; ações no GitHub.

- [ ] **Step 1: Verificação local completa**

Run: `actionlint && find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -r shellcheck -x && bash tests/run.sh && grep -rn 'SthoreH' .github actions scripts || echo "sem referências à SthoreH"`
Expected: linters sem saída; todos os testes `PASS`; `sem referências à SthoreH`

- [ ] **Step 2: Revisão antes do PR**

Dispatch do agente `revisor-pr` (workspace) sobre `feature/workflows-infra` contra `dev`. Corrigir bloqueantes na mesma branch.

- [ ] **Step 3: PR para `dev`**

```bash
git push -u origin feature/workflows-infra
gh pr create --base dev --title "feat: workflows reutilizáveis de infra da fase 0" --body "$(cat <<'EOF'
## O que entra
- Workflows reutilizáveis: ci-infra-terraform, cd-infra-terraform, ci-terraform-module, pr-validation, release-semantic, rollback-infra, destroy-infra
- Actions: validate-pr, parse-config, setup-terraform-aws, terraform-plan, terraform-apply, replace-tokens, changed-modules, parse-issue
- Release deste repositório com cálculo de versão e reescrita de referências em scripts testados
- Docs: catálogo, convenções do consumidor e uma página por workflow; spec alinhada

## Como foi validado
- Testes unitários em bash (tests/run.sh): versão, reescrita de referências, fluxo de branches, título, parse-config, replace-tokens, changed-modules, parse-issue
- Self-test no CI: parse-config → setup → plan com mudança → apply → plan sem mudança → apply de plano vazio, contra tests/fixtures/infra-basic (sem AWS)
- actionlint e shellcheck sem achados

Os workflows reutilizáveis só são exercitados de ponta a ponta quando um consumidor apontar para a tag (plano da migração fundação → plataforma).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: checks `Lint`, `Unit tests`, `Self-test` e `Validate Pull Request` verdes

- [ ] **Step 4: Merge em `dev` e promoção**

Com checks verdes **e** autorização do usuário: `gh pr merge <n> --merge --delete-branch`. Este repositório não tem deploy: abrir em seguida `gh pr create --base main --head dev --title "feat: workflows reutilizáveis de infra da fase 0"`. **O merge em `main` é do usuário.**

- [ ] **Step 5: Conferir o release (após o merge em `main`)**

Run:
```bash
gh run list --workflow Release --branch main --limit 1
git fetch --tags && v=$(git tag --list 'v*' --sort=-v:refname | head -1) && echo "$v"
git grep -n 'shd-github-actions-workflows/\(actions\|.github/workflows\)/.*@main' "$v" -- .github/workflows || echo "nenhuma referência interna @main na tag"
git grep -c "@$v" "$v" -- .github/workflows
```
Expected: run `success`; tag `v1.1.0`; `nenhuma referência interna @main na tag`; contagens > 0 nos workflows reutilizáveis

- [ ] **Step 6: Rulesets (repositório público)**

Create `/tmp/ruleset.json`:

```json
{
  "name": "dev-e-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/dev", "refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": { "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": true, "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": false, "required_status_checks": [
      { "context": "Lint" }, { "context": "Unit tests" }, { "context": "Self-test" }, { "context": "Validate Pull Request" } ] } }
  ],
  "bypass_actors": []
}
```

Run: `gh api -X POST repos/MegaMixDistribuidora/shd-github-actions-workflows/rulesets --input /tmp/ruleset.json --jq '.id, .enforcement'`
Expected: id numérico e `active`

Nota: o release deste repositório só faz push de **tag**, então o ruleset de branches não o bloqueia.

- [ ] **Step 7: Registrar o fim do plano**

Apagar este plano numa `feature/*` com PR (regra 4 de documentação do workspace: plano executado é apagado; o histórico fica no git).
