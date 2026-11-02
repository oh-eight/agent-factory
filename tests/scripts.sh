#!/usr/bin/env bash
# Runs every skills/*/scripts/<name>.sh against its fixture cases in
# tests/fixtures/<name>/<case>/. A case holds `args` (one line of
# whitespace-separated words, no quoting, never glob-expanded),
# `expected-stdout` (exact bytes), `expected-exit` (a decimal exit code) and
# any data files; the script runs with the case dir as working directory and
# stderr is not compared. Prints one line per failure and exits 1 on any;
# prints "scripts ok" otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

fail=0
bad() { echo "FAIL: $*"; fail=1; }

TMP="$(mktemp -d)" || { echo "FAIL: tests/scripts.sh: cannot create a temp directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# 1. A script name lives in one skill only.
dups="$(for s in skills/*/scripts/*.sh; do [ -f "$s" ] && basename "$s"; done | sort | uniq -d)"
if [ -n "$dups" ]; then
  while IFS= read -r d; do
    paths=""
    for s in skills/*/scripts/"$d"; do [ -f "$s" ] && paths="$paths $s"; done
    bad "${d%.sh}: two scripts:$paths"
  done <<< "$dups"
fi

# 2. Every script has at least one fixture case.
for s in skills/*/scripts/*.sh; do
  [ -f "$s" ] || continue
  name="$(basename "$s" .sh)"
  has=0
  for c in "tests/fixtures/$name"/*/; do
    [ -d "$c" ] && { has=1; break; }
  done
  [ "$has" = 1 ] || bad "$s: no fixtures"
done

# 3. Every fixture dir belongs to exactly one script, and every case passes.
for fx in tests/fixtures/*/; do
  [ -d "$fx" ] || continue
  name="$(basename "$fx")"
  script=""
  count=0
  for s in skills/*/scripts/"$name".sh; do
    [ -f "$s" ] || continue
    script="$ROOT/$s"
    count=$((count + 1))
  done
  if [ "$count" = 0 ]; then
    bad "$name: no script"
    continue
  fi
  [ "$count" = 1 ] || continue # reported in check 1
  for case_dir in "$fx"*/; do
    [ -d "$case_dir" ] || continue
    c="$name/$(basename "$case_dir")"
    missing=0
    for f in args expected-stdout expected-exit; do
      [ -f "$case_dir/$f" ] || { bad "$c: missing $f"; missing=1; }
    done
    [ "$missing" = 0 ] || continue
    want="$(tr -d '[:space:]' < "$case_dir/expected-exit")"
    case "$want" in
      ''|*[!0-9]*) bad "$c: expected-exit is not a decimal integer"; continue ;;
    esac
    ( cd "$case_dir" && set -f && exec "$script" $(cat args) ) > "$TMP/out" 2>/dev/null
    got=$?
    [ "$got" -eq "$want" ] || bad "$c: exit $got want $want"
    cmp -s "$TMP/out" "$case_dir/expected-stdout" || bad "$c: stdout differs"
  done
done

if [ "$fail" -eq 0 ]; then
  echo "scripts ok"
  exit 0
fi
exit 1
