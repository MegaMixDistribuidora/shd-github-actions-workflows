#!/usr/bin/env bash
# Assertions mínimas para testes em bash. Uso: source tests/lib.sh
set -uo pipefail
FAILS=0

assert_eq() { # <esperado> <obtido> <mensagem>
  if [[ "$1" == "$2" ]]; then
    echo "  ok   $3"
  else
    echo "  FAIL $3"
    echo "       esperado: $1"
    echo "       obtido:   $2"
    FAILS=$((FAILS + 1))
  fi
}

assert_exit() { # <código> <mensagem> -- <comando...>
  local want=$1 msg=$2
  shift 3
  "$@" >/dev/null 2>&1
  assert_eq "$want" "$?" "$msg"
}

finish() {
  if [[ $FAILS -eq 0 ]]; then echo "PASS"; else echo "$FAILS falha(s)"; exit 1; fi
}
