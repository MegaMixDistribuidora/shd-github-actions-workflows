#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
SCRIPT="$(pwd)/scripts/tag-release.sh"
echo "tag-release"
repo=$(mktemp -d); cd "$repo" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m "chore: inicial"
bash "$SCRIPT" 1.0.0
assert_eq "$(git rev-parse HEAD)" "$(git rev-parse 'v1.0.0^{commit}')" "v1.0.0 no commit atual da main"
assert_eq "$(git rev-parse HEAD)" "$(git rev-parse 'v1^{commit}')" "major v1 criada no mesmo commit"
git commit -q --allow-empty -m "feat: x"; c2=$(git rev-parse HEAD)
bash "$SCRIPT" 1.1.0
assert_eq "$c2" "$(git rev-parse 'v1^{commit}')" "major v1 movida para o release novo"
assert_eq "$(git rev-parse HEAD~1)" "$(git rev-parse 'v1.0.0^{commit}')" "v1.0.0 continua onde estava"
git commit -q --allow-empty -m "feat!: y"
bash "$SCRIPT" 2.0.0
assert_eq "$c2" "$(git rev-parse 'v1^{commit}')" "major nova não mexe na v1"
assert_eq "$(git rev-parse HEAD)" "$(git rev-parse 'v2^{commit}')" "major v2 criada"
assert_exit 1 "versão inválida é recusada" -- bash "$SCRIPT" v3
assert_exit 1 "tag existente é recusada" -- bash "$SCRIPT" 2.0.0
cd / && rm -rf "$repo"
finish
