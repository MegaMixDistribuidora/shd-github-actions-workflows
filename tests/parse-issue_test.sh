#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
S=actions/parse-issue/parse-issue.sh
echo "parse-issue"
body=$'### Ambiente\r\n\r\nprod\r\n\r\n### Tag ou Release alvo\r\n\r\n  v1.2.3  \r\n\r\n### Confirmação\r\n\r\naws-megamix-infra\r\n'
assert_eq "prod" "$(ISSUE_BODY=$body bash "$S" "Ambiente")" "campo com CRLF"
assert_eq "v1.2.3" "$(ISSUE_BODY=$body bash "$S" "Tag ou Release alvo")" "espaços nas pontas removidos"
assert_eq "aws-megamix-infra" "$(ISSUE_BODY=$body bash "$S" "Confirmação")" "campo com acento"
assert_exit 1 "campo ausente falha" -- env ISSUE_BODY="$body" bash "$S" "Motivo"
assert_exit 1 "campo com '_No response_' falha" -- env ISSUE_BODY=$'### Motivo\n\n_No response_\n' bash "$S" "Motivo"
finish
