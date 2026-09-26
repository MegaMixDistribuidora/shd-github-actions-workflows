# destroy-infra.yml

Com a label `destroy-approved`: **somente dev**, e o campo **Confirmação** deve ser exatamente o nome do repositório. `plan -destroy` salvo e apply do plano. Comenta e fecha a issue em caso de sucesso.

Chamador: `on: issues (types: labeled)`; permissões `contents: read`, `id-token: write`, `issues: write`.
