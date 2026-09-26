#!/usr/bin/env bash
# Instala em ~/.local/bin as ferramentas usadas pelos testes e pelo lint locais.
# Os runners do GitHub já têm yq, jq e shellcheck; actionlint é baixado no CI.
set -euo pipefail
BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
curl -sSfL -o "$BIN/yq" https://github.com/mikefarah/yq/releases/download/v4.53.6/yq_linux_amd64
curl -sSfL -o "$BIN/jq" https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
chmod +x "$BIN/yq" "$BIN/jq"
curl -sSfL https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz \
  | tar -xJ -C /tmp && mv /tmp/shellcheck-v0.10.0/shellcheck "$BIN/"
(cd "$BIN" && bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash) 1.7.12)
echo "Ferramentas em $BIN — garanta que ele está no PATH."
