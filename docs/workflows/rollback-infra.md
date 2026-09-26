# rollback-infra.yml

Com a label `rollback-approved` numa issue do template de rollback: lê **Ambiente** e **Tag ou Release alvo**, confere que a tag existe e chama o `cd-infra-terraform.yml` com `ref` = tag. Comenta o resultado na issue.

Chamador: `on: issues (types: labeled)`; permissões `contents: read`, `id-token: write`, `issues: write`.
