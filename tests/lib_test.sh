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
