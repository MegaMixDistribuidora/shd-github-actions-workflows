<!-- Canônico em megamix-workspace/.claude/rules. Nos repositórios, esta é uma cópia gerada por sync-repos.sh: edite no workspace. -->
# Segurança (regras rígidas)

1. **Nenhum segredo em repositório** — nem em código, tfvars, `.pipeline.yml`, workflows, docs, fixtures, commits ou PRs. Segredos só no AWS Secrets Manager; credenciais da esteira só em secrets do GitHub Environment.
2. **Nenhum dado pessoal** (e-mail, CPF/CNPJ, telefone, endereço reais) em código, testes, fixtures, exemplos ou logs. Use dados fictícios.
3. Repositórios públicos (`shd-*`, `tpl-*`) são genéricos: nada de regra de negócio, preço, cliente ou dado da Mega Mix.
4. **Suspeita de segredo commitado:** pare e avise o usuário. Credencial exposta se **rotaciona** — apagar o commit não basta.
