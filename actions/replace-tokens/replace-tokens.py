"""Substitui ${pipe_<chave>} nos arquivos listados pelos valores do parse-config.

Variáveis: FILES (separados por espaço), CONFIG (JSON plano do parse-config).
Tokens sem valor conhecido ficam como estão.
"""
import json
import os
import re
import sys

config = json.loads(os.environ.get("CONFIG") or "{}")
files = (os.environ.get("FILES") or "").split()
token = re.compile(r"\$\{(pipe_[A-Za-z0-9_.-]+)\}")

for path in files:
    if not os.path.isfile(path):
        print(f"::error::arquivo para substituição não encontrado: {path}")
        sys.exit(1)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = token.sub(lambda m: str(config[m.group(1)]) if m.group(1) in config else m.group(0), text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"tokens substituídos em {path}")
