#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
SCRIPT="$(pwd)/scripts/next-version.sh"
echo "next-version"

repo=$(mktemp -d)
cd "$repo" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
commit() { git commit -q --allow-empty -m "$1"; }
release_detached() { # simula o release: commit fora da main + tag
  local v; v=$(bash "$SCRIPT"); [[ -z "$v" ]] && { echo ""; return; }
  git checkout -q --detach; commit "chore(release): v$v"; git tag -a "v$v" -m "v$v"; git checkout -q main; echo "v$v"
}
release_on_main() { # simula o release sem commit de reescrita: tag na própria main
  local v; v=$(bash "$SCRIPT"); git tag -a "v$v" -m "v$v"; echo "v$v"
}

commit "chore: commit inicial"
assert_eq "v1.0.0" "$(release_on_main)" "primeiro release é 1.0.0"
assert_eq "" "$(bash "$SCRIPT")" "tag na própria main: sem commit novo, sem release"
commit "docs: ajuste"
assert_eq "v1.0.1" "$(release_detached)" "docs gera patch (tag anterior na main)"
assert_eq "" "$(bash "$SCRIPT")" "tag fora da main: sem commit novo, sem release"
commit "feat: novo workflow"; commit "fix: corrige"
assert_eq "v1.1.0" "$(release_detached)" "feat gera minor"
commit "feat(ci)!: muda inputs"
assert_eq "v2.0.0" "$(release_detached)" "feat! com escopo gera major"
commit $'refactor: y\n\nBREAKING CHANGE: remove input'
assert_eq "v3.0.0" "$(release_detached)" "BREAKING CHANGE no corpo gera major"
commit "Merge pull request #9 from x/dev"
assert_eq "v3.0.1" "$(release_detached)" "merge commit gera patch"
cd / && rm -rf "$repo"
finish
