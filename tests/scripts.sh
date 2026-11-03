#!/usr/bin/env bash
# Runs every skills/*/scripts/<name>.sh against tests/fixtures/<name>/cases.
# The fixture dir holds the base data files and one `cases` file; each case
# starts from a fresh copy of the base files, applies its optional patch,
# runs the script there with its args, and compares exit code and stdout
# (stderr is not compared). Format: see the header of any `cases` file.
# Prints one line per failure and exits 1 on any; prints "scripts ok"
# otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

fail=0
bad() { echo "FAIL: $*"; fail=1; }

TMP="$(mktemp -d)" || { echo "FAIL: tests/scripts.sh: cannot create a temp directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Split a cases file into $2/<n>/{name,args,exit,stdout,patch}, byte for
# byte (LC_ALL=C: a UTF-8 awk aborts on the invalid-UTF-8 case records).
split_cases() {
  LC_ALL=C awk -v out="$2" '
    function open_case() { n++; dir = out "/" n; system("mkdir -p \"" dir "\""); sect = "" }
    /^=== / { open_case(); print substr($(0), 5) > (dir "/name"); next }
    n == 0 { next }
    sect == "" && /^args: / { print substr($(0), 7) > (dir "/args"); next }
    sect == "" && /^exit: / { print substr($(0), 7) > (dir "/exit"); next }
    /^stdout:$/ { sect = "stdout"; printf "" > (dir "/stdout"); next }
    /^patch:$/  { sect = "patch"; next }
    sect == "stdout" && /^$/ { next }
    sect != "" { print > (dir "/" sect) }
  ' "$1"
}

# 1. A script name lives in one skill only.
dups="$(for s in skills/*/scripts/*.sh; do [ -f "$s" ] && basename "$s"; done | sort | uniq -d)"
for d in $dups; do bad "${d%.sh}: two scripts:$(ls -d skills/*/scripts/"$d" | tr '\n' ' ')"; done

# 2. Every script has a cases file.
for s in skills/*/scripts/*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s" .sh)"
  [ -f "tests/fixtures/$name/cases" ] || bad "$s: no tests/fixtures/$name/cases"
done

# 3. Every fixture dir belongs to one script, and every case passes.
for fx in tests/fixtures/*/ tests/fixtures/.*/; do
  [ -d "$fx" ] || continue
  name="$(basename "$fx")"
  case "$name" in .|..) continue ;; esac
  set -- skills/*/scripts/"$name".sh
  [ -f "$1" ] || { bad "$name: no script"; continue; }
  [ $# = 1 ] || continue # reported in check 1
  script="$ROOT/$1"
  [ -f "$fx/cases" ] || continue # reported in check 2
  rm -rf "$TMP/cases"; mkdir -p "$TMP/cases"
  split_cases "$fx/cases" "$TMP/cases"
  total=0
  for cd_ in "$TMP/cases"/*/; do
    [ -d "$cd_" ] || continue
    total=$((total + 1))
    c="$name/$(cat "$cd_/name")"
    for f in args exit stdout; do
      [ -f "$cd_/$f" ] || { bad "$c: no $f"; continue 2; }
    done
    want="$(cat "$cd_/exit")"
    case "$want" in ''|*[!0-9]*) bad "$c: exit is not one decimal integer"; continue ;; esac
    rm -rf "$TMP/run"; cp -R "$fx" "$TMP/run"; rm -f "$TMP/run/cases"
    if [ -f "$cd_/patch" ] && ! (cd "$TMP/run" && patch -s -p0 < "$cd_/patch" > /dev/null 2>&1); then
      bad "$c: patch does not apply"; continue
    fi
    ( cd "$TMP/run" && set -f && exec "$script" $(cat "$cd_/args") ) > "$TMP/out" 2>/dev/null
    got=$?
    [ "$got" -eq "$want" ] || bad "$c: exit $got want $want"
    cmp -s "$TMP/out" "$cd_/stdout" || bad "$c: stdout differs"
  done
  [ "$total" -gt 0 ] || bad "$name: cases file has no cases"
done

if [ "$fail" -eq 0 ]; then
  echo "scripts ok"
  exit 0
fi
exit 1
