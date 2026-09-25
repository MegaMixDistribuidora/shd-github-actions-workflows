# Fluxo Git (regras rígidas)

Valem para todo commit, push e PR neste repositório, inclusive quando a sessão é aberta direto aqui ou na nuvem.

1. **Fluxo único: `feature/<nome>` → `dev` → `main`.** A branch nasce de `dev` atualizada. Correção também é `feature/*`; o tipo vai no commit (`fix:`).
2. **Nunca commitar nem fazer push direto em `dev` ou `main`.** Única exceção: o commit inicial de um repositório vazio.
3. **Toda mudança entra por PR:** `feature/*` → `dev` e `dev` → `main`. Nenhuma outra origem ou destino.
4. Feature concluída: push da branch e `gh pr create --base dev --title "<tipo>: <resumo>"`. Check vermelho se corrige na mesma feature.
5. **Merge em `dev`:** o Claude só faz com **todos os checks verdes e autorização explícita do usuário** na conversa. O merge dispara o CD de dev.
6. **Merge em `main` é sempre do usuário.** O Claude só abre o PR `dev` → `main` quando pedido. O merge dispara o CD de prod.
7. **Nunca contornar a esteira:** sem `--no-verify`, force push, `gh pr merge --admin` ou checks desligados.
8. Commits e títulos de PR em Conventional Commits, em português (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).

O hook `.claude/hooks/guard-git.py` bloqueia localmente as violações das regras 2, 5 e 6. Se ele bloquear um comando, não tente contorná-lo: crie a feature, abra o PR ou pergunte ao usuário.
