#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "pin-internal-refs"
f=$(mktemp)
cat > "$f" <<'YAML'
      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@main
      - uses: "MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@v1.0.0"
    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@main
      - uses: actions/checkout@v7
YAML
bash scripts/pin-internal-refs.sh 1.2.3 "$f"
assert_eq "      - uses: MegaMixDistribuidora/shd-github-actions-workflows/actions/parse-config@v1.2.3" "$(sed -n 1p "$f")" "action interna @main"
assert_eq '      - uses: "MegaMixDistribuidora/shd-github-actions-workflows/actions/setup-terraform-aws@v1.2.3"' "$(sed -n 2p "$f")" "action interna entre aspas"
assert_eq "    uses: MegaMixDistribuidora/shd-github-actions-workflows/.github/workflows/cd-infra-terraform.yml@v1.2.3" "$(sed -n 3p "$f")" "workflow interno"
assert_eq "      - uses: actions/checkout@v7" "$(sed -n 4p "$f")" "action de terceiro intacta"
assert_exit 1 "versão inválida é recusada" -- bash scripts/pin-internal-refs.sh v1 "$f"
rm -f "$f"
finish
