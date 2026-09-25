#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
S="$(pwd)/actions/require-admin/require-admin.sh"
echo "require-admin"
fake=$(mktemp -d)
# gh falso: devolve a permissão definida em FAKE_PERMISSION
cat > "$fake/gh" <<'SH'
#!/usr/bin/env bash
echo "${FAKE_PERMISSION}"
SH
chmod +x "$fake/gh"
run() { PATH="$fake:$PATH" ENVIRONMENT=$1 FAKE_PERMISSION=$2 SENDER=alguem REPOSITORY=org/repo bash "$S"; }
assert_exit 0 "dev não exige admin" -- run dev write
assert_exit 0 "prod com admin é aceito" -- run prod admin
assert_exit 1 "prod com write é recusado" -- run prod write
assert_exit 1 "prod com triage é recusado" -- run prod triage
assert_exit 1 "prod sem SENDER é recusado" -- env PATH="$fake:$PATH" ENVIRONMENT=prod FAKE_PERMISSION=admin REPOSITORY=org/repo bash "$S"
rm -rf "$fake"
finish
