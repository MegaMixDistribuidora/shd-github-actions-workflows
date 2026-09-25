<!-- Canônico em megamix-workspace/.claude/rules. Nos repositórios, esta é uma cópia gerada por sync-repos.sh: edite no workspace. -->
# Fluxo Git (regras rígidas)

1. **Fluxo único: `feature/<nome>` → `dev` → `main`.** A branch nasce de `dev` atualizada, com o mesmo nome em todos os repositórios afetados. Correção também é `feature/*`; o tipo vai no commit (`fix:`).
2. **Nunca commitar nem fazer push direto em `dev` ou `main`.** Única exceção: o commit inicial de um repositório vazio (cria a `main`; a `dev` sai dela).
3. **Toda mudança entra por PR:** `feature/*` → `dev` e `dev` → `main`. Nenhuma outra origem ou destino.
4. Feature concluída: push e `gh pr create --base dev --title "<tipo>: <resumo>"`. Check vermelho se corrige na mesma feature.
5. **Merge em `dev`:** o Claude só faz com **todos os checks verdes e autorização explícita do usuário** na conversa. Dispara o CD de dev. **Se o Deploy Dev ficar verde, o Claude abre em seguida o PR `dev` → `main`** (com o resultado do deploy na descrição) e confere o CI de prod; se o deploy falhar, corrige numa `feature/*` antes de promover.
6. **Merge em `main` é sempre do usuário.** Dispara o CD de prod e o release (regra 7).
7. **Todo commit na `main` gera tag `vX.Y.Z` e GitHub Release** (ADR-14): `feat` → minor, `BREAKING CHANGE` → major, qualquer outro tipo → patch. O release nunca commita na `main`.
8. **Nunca contornar a esteira:** sem `--no-verify`, force push, `gh pr merge --admin` ou checks desligados.
9. Commits e títulos de PR em Conventional Commits, em português (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).

O hook `.claude/hooks/guard-git.py` bloqueia localmente as violações das regras 2, 5 e 6. Se ele bloquear um comando, não o contorne: crie a feature, abra o PR ou pergunte ao usuário.
