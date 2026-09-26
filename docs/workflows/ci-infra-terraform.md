# ci-infra-terraform.yml

Plan de infra em PR, com lint (tflint; checkov em relatório) e comentário no PR (um por ambiente, atualizado a cada push).

| Input | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `environment` | string | sim | `dev` ou `prod` — GitHub Environment e `environments/<ambiente>.tfvars` |

Permissões do job chamador: `contents: read`, `id-token: write`, `pull-requests: write`. Job: `Validate Infrastructure`.
