# cd-infra-terraform.yml

Plan salvo e apply do mesmo plano. Concorrência `<repositório>-<ambiente>`, sem cancelar apply em andamento.

| Input | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `environment` | string | sim | `dev` ou `prod` |
| `ref` | string | não | tag a reaplicar (rollback); vazio = commit do evento |

Permissões do job chamador: `contents: read`, `id-token: write`. Job: `Deploy Infrastructure`.
