#!/usr/bin/env python3
"""PreToolUse hook (Bash): enforces the Mega Mix branch flow feature/* -> dev -> main.

Blocks (exit 2, reason on stderr):
  - git commit while the target repository is on dev or main
    (except the initial commit of an empty repository);
  - git push whose destination is dev or main, a plain push from dev/main,
    and --all / --mirror;
  - gh pr merge into main, with --admin, or while any check is not green.

Parses every command segment (&&, ||, ;, |, subshells), follows `cd <dir>`,
`git -C <dir>` and nested `bash -c "..."`. Fails closed when the PR state
cannot be read.
"""
import json
import os
import shlex
import subprocess
import sys

PROTECTED = {"dev", "main"}
SEPARATORS = {"&&", "||", ";", "|", "&", "(", ")", "\n", ";;", "|&"}
SHELLS = {"bash", "sh", "zsh"}


def block(reason: str) -> None:
    print(f"Bloqueado pelo guard-git (fluxo feature/* -> dev -> main): {reason}", file=sys.stderr)
    sys.exit(2)


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True)


def current_branch(repo_dir):
    result = run(["git", "symbolic-ref", "--short", "-q", "HEAD"], repo_dir)
    return result.stdout.strip() if result.returncode == 0 else None


def has_commits(repo_dir):
    return run(["git", "rev-parse", "--verify", "-q", "HEAD"], repo_dir).returncode == 0


def tokenize(command):
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    return list(lexer)


def segments(tokens):
    current = []
    for token in tokens:
        if token in SEPARATORS:
            if current:
                yield current
            current = []
        else:
            current.append(token)
    if current:
        yield current


def strip_prefix(seg):
    """Drops env assignments and wrappers such as `sudo`, `env`, `command`."""
    i = 0
    while i < len(seg) and ("=" in seg[i] and not seg[i].startswith("-") and seg[i].split("=", 1)[0].isidentifier()):
        i += 1
    while i < len(seg) and seg[i] in {"sudo", "env", "command", "exec", "time", "nohup"}:
        i += 1
    return seg[i:]


def resolve(path, cwd):
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(path)))


def check_git(args, cwd):
    repo = cwd
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            repo = resolve(args[i + 1], repo)
            i += 2
        elif args[i] in {"-c", "--git-dir", "--work-tree", "--namespace"} and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1:]
    if sub == "commit":
        branch = current_branch(repo)
        if branch in PROTECTED and has_commits(repo):
            block(f"commit direto em '{branch}' ({repo}). Crie uma branch feature/<nome> a partir de dev.")
    elif sub == "push":
        check_push(rest, repo)


def ref_name(ref):
    ref = ref.lstrip("+")
    for prefix in ("refs/heads/",):
        if ref.startswith(prefix):
            ref = ref[len(prefix):]
    return ref


def check_push(rest, repo):
    positional = []
    skip_next = False
    for token in rest:
        if skip_next:
            skip_next = False
            continue
        if token in {"--all", "--mirror"}:
            block(f"'git push {token}' atualizaria dev/main.")
        if token in {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}:
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        positional.append(token)
    refspecs = positional[1:]
    if not refspecs:
        branch = current_branch(repo)
        if branch in PROTECTED:
            block(f"push a partir de '{branch}'. Mudanças entram por PR de uma feature/*.")
        return
    for spec in refspecs:
        dest = spec.split(":", 1)[1] if ":" in spec else spec
        dest = ref_name(dest)
        if dest == "HEAD":
            dest = current_branch(repo) or ""
        if dest in PROTECTED:
            block(f"push para '{dest}'. Abra um PR (feature/* -> dev ou dev -> main).")


def check_gh(args, cwd):
    if len(args) < 2 or args[0] != "pr" or args[1] != "merge":
        return
    rest = args[2:]
    if "--admin" in rest:
        block("'gh pr merge --admin' contorna os checks.")
    selector, repo_flag = [], []
    skip_next = None
    for token in rest:
        if skip_next:
            if skip_next in {"-R", "--repo"}:
                repo_flag = ["-R", token]
            skip_next = None
            continue
        if token in {"-R", "--repo", "-b", "--body", "-F", "--body-file", "-t", "--subject",
                     "-A", "--author-email", "--match-head-commit"}:
            skip_next = token
            continue
        if token.startswith("--repo="):
            repo_flag = ["-R", token.split("=", 1)[1]]
            continue
        if token.startswith("-"):
            continue
        selector.append(token)
    target = selector[:1]
    view = run(["gh", "pr", "view", *target, *repo_flag, "--json", "baseRefName,number"], cwd)
    if view.returncode != 0:
        block("não foi possível ler o PR para validar base e checks (gh pr view falhou).")
    pr = json.loads(view.stdout)
    if pr.get("baseRefName") == "main":
        block(f"PR #{pr.get('number')} tem base 'main'. O merge em main é sempre do usuário.")
    checks = run(["gh", "pr", "checks", str(pr.get("number")), *repo_flag], cwd)
    if checks.returncode != 0:
        block(f"PR #{pr.get('number')} tem checks pendentes ou falhando (gh pr checks).")


def inspect(command, cwd):
    for seg in segments(tokenize(command)):
        seg = strip_prefix(seg)
        if not seg:
            continue
        head = os.path.basename(seg[0])
        if head == "cd" and len(seg) > 1:
            cwd = resolve(seg[1], cwd)
        elif head == "git":
            check_git(seg[1:], cwd)
        elif head == "gh":
            check_gh(seg[1:], cwd)
        elif head in SHELLS and "-c" in seg:
            idx = seg.index("-c")
            if idx + 1 < len(seg):
                inspect(seg[idx + 1], cwd)
    return cwd


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    command = (data.get("tool_input") or {}).get("command") or ""
    if not any(word in command for word in ("git", "gh")):
        return
    cwd = data.get("cwd") or os.getcwd()
    try:
        inspect(command, cwd)
    except ValueError:
        # Unbalanced quotes: fall back to a conservative textual check.
        if "commit" in command or "push" in command or "merge" in command:
            block("comando git/gh que não pôde ser analisado com segurança; reescreva sem aspas desbalanceadas.")


if __name__ == "__main__":
    main()
