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
assert_exit 0 "só README termina com sucesso (pipefail não derruba)" -- bash "$SCRIPT" "$b3" HEAD
b4=$(git rev-parse HEAD); echo x > .github/ci.yml && git add -A && git commit -qm ci
assert_eq $'a\nb' "$(bash "$SCRIPT" "$b4" HEAD)" "mudança em .github valida todos"
b5=$(git rev-parse HEAD); mkdir -p examples/z && echo x > examples/z/main.tf && git add -A && git commit -qm z
assert_eq "" "$(bash "$SCRIPT" "$b5" HEAD)" "exemplo sem módulo correspondente é ignorado"
assert_exit 0 "exemplo sem módulo termina com sucesso" -- bash "$SCRIPT" "$b5" HEAD
cd / && rm -rf "$repo"
finish
