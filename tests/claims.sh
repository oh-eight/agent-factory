#!/usr/bin/env bash
# Acceptance tests for oh-eight/agent-factory#2: lint-report.sh, the
# tests/scripts.sh and tests/lint.sh runners, and the adversarial-review
# SKILL.md and README text. One function per spec claim (t_C1 .. t_C31).
#
#   bash tests/claims.sh            # every claim
#   bash tests/claims.sh C4 C17     # only these claims
#
# Prints "ok C<n>" per passing claim and "FAIL: C<n>: ..." per failed check,
# then "claims ok" and exit 0 when everything passed, else exit 1.
# Never edits the checkout: mutations run on copies under a temp directory.
# C14 needs commit 18e2a1a (the pre-change inline lint) in the history.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
L="$REPO/skills/adversarial-review/scripts/lint-report.sh"
F="$REPO/tests/fixtures/lint-report"
M="$REPO/skills/adversarial-review/SKILL.md"
BASE=18e2a1a

TMP="$(mktemp -d)" || { echo "FAIL: tests/claims.sh: cannot create a temp directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

fail=0
cur=""
bad() { echo "FAIL: $cur: $*"; fail=1; }

# check <label> <got> <want>: exact string comparison, shows both on failure.
check() {
  [ "$2" = "$3" ] && return 0
  bad "$1"
  printf '%s\n' "$3" | sed 's/^/    want| /'
  printf '%s\n' "$2" | sed 's/^/    got | /'
}

# atleast <label> <got> <min>
atleast() {
  case "$2" in ''|*[!0-9]*) bad "$1: not a count: [$2]"; return ;; esac
  [ "$2" -ge "$3" ] || bad "$1: got $2, want at least $3"
}

lines() { printf '%s\n' "$@"; }

# work [src]: a fresh copy of a fixture case's spec.md and round.md.
work() {
  local w
  w="$(mktemp -d "$TMP/w.XXXXXX")"
  cp "$F/${1:-good}/spec.md" "$F/${1:-good}/round.md" "$w/"
  echo "$w"
}

# lint_in <dir> <args...>: the script's stdout, then exit=<status>.
lint_in() {
  local d="$1"
  shift
  ( cd "$d" && { "$L" "$@" 2>/dev/null; echo "exit=$?"; } )
}

# on <src> <mutation fn> <args...>: mutate a fresh copy, lint it.
on() {
  local src="$1" m="$2" w
  shift 2
  w="$(work "$src")"
  ( cd "$w" && "$m" ) || { echo "mutation $m failed"; return; }
  lint_in "$w" "$@"
}

# repo_copy: a scratch copy of the repo, as the spec's How to run says.
repo_copy() {
  local c
  c="$(mktemp -d "$TMP/c.XXXXXX")/repo"
  mkdir -p "$c"
  cp -R "$REPO/skills" "$REPO/tests" "$REPO/install.sh" "$REPO/README.md" "$c/"
  echo "$c"
}

none() { :; }

# Mutations of a fresh good copy (run inside the copy).
m_c4_done()      { sed -i 's/^verdict: FINDINGS$/verdict: DONE/' round.md; }
m_c4_second()    { printf 'verdict: CLEAN\n' >> round.md; }
m_c4_trailing()  { sed -i 's/^verdict: FINDINGS$/verdict: CLEAN /' round.md; }
m_c4_capital()   { sed -i 's/^verdict: FINDINGS$/Verdict: CLEAN/' round.md; }
m_c4_nospace()   { sed -i 's/^verdict: FINDINGS$/verdict:CLEAN/' round.md; }
m_c4_none()      { sed -i '/^verdict: /d' round.md; }
m_c5_extra()     { printf '\n### C5: extra\n- type: functional\n' >> spec.md; }
m_c5_unremoved() { sed -i '/^- status: removed-r1$/d' spec.md; }
m_c5_unknown()   { sed -i '/^### C4:/d' spec.md; }
m_c7_noux()      { sed -i 's/^- type: ux$/- type: functional/' spec.md; }
m_c7_critic()    { sed -i 's/^personas: .*/personas: fuzzer, attacker, stranger, critic/' round.md; }
m_c8_nofinding() { sed -i 's/^### C4 — FAIL → F-1-1$/### C4 — FAIL/' round.md; }
m_c8_norepro()   { sed -i '/^- repro:/d' round.md; }
m_c8_reason()    {
  sed -i 's/^### C4 — FAIL → F-1-1$/### C4 — UNVERIFIABLE → F-1-1/; s/^- repro: .*/- reason: no compiler in the sandbox/; s/^claims: .*/claims: 3  pass: 2  fail: 0  unverifiable: 1  attempts: 12  deferred: 0/' round.md
}
m_c8_dangling()  { sed -i 's/^### C4 — FAIL → F-1-1$/### C4 — FAIL → F-1-99/' round.md; }
m_c9_outside()   { sed -i 's|^## Files opened$|## Files opened\nlib/internal.c|' round.md; }
m_c9_exempt()    { sed -i 's|^## Files opened$|## Files opened\n$HOME/x.c\n~/y.h\n/opt/z.cpp\nnotes.md\nrun.sh|' round.md; }
m_c13_999()      { sed -i 's/attempts: 12/attempts: 999/' round.md; }
m_c13_gone()     { sed -i '/^## Coverage$/,$d' round.md; }
m_c13_squeezed() { sed -i 's/^claims: .*/claims: 3 pass: 2 fail: 1 unverifiable: 0 attempts: 12 deferred: 0/' round.md; }
m_c16_empty()    { : > round.md; }
m_c16_garbage()  { head -c 2000 /dev/urandom > round.md; }
m_c16_nospec()   { : > spec.md; }
m_c17_inject()   {
  touch a.c b.c
  sed -i 's|^## Files opened$|## Files opened\n$(touch${IFS}pwned).c\n*.c\n-rf.c|' round.md
  sed -i 's/^personas: .*/personas: fuzzer, attacker, stranger, $(touch${IFS}pwned3)/' round.md
}
m_c17_more()     {
  sed -i 's|^## Files opened$|## Files opened\n`touch${IFS}pwned4`.c\n;touch${IFS}pwned5;.c\n"q%s".c|' round.md
  sed -i 's/^personas: .*/personas: fuzzer, attacker, stranger, "q%s"/' round.md
}
m_c18_pattern()  {
  sed -i 's|^## Entry points$|## Entry points\n.*\nlib/.*|' spec.md
  sed -i 's|^## Files opened$|## Files opened\nlib/internal.c|' round.md
}
m_c18_regexpath() { sed -i 's|^## Files opened$|## Files opened\nbin/too..c\n[b]in/tool.c|' round.md; }
m_c14_many()     {
  local i
  for i in 5 6 7 8 9 10 11 12; do printf '\n### C%s: more\n- type: functional\n' "$i" >> spec.md; done
  sed -i 's/^### C4 — FAIL → F-1-1$/### C10 — PASS\n- attempts (fuzzer):\n  1. x\n\n### C4 — FAIL → F-1-1/' round.md
}
m_c14_nocommas() { sed -i 's/^personas: .*/personas: fuzzer attacker stranger/' round.md; }
m_c14_tenth()    { sed -i '0,/^  3\. /s//  3. x\n  10. /' round.md; }
m_c14_nofiles()  { sed -i '/^## Files opened$/,/^## /{/^## /!d}' round.md; }
m_c14_crlf()     { sed -i 's/$/\r/' round.md; }

# Every default-mode mutation, for the C14 oracle comparison.
DEFAULT_MUTATIONS="m_c4_done m_c4_second m_c4_trailing m_c4_capital m_c4_nospace m_c4_none
  m_c5_extra m_c5_unremoved m_c5_unknown m_c7_noux m_c7_critic m_c8_nofinding m_c8_norepro
  m_c8_reason m_c8_dangling m_c9_outside m_c9_exempt m_c13_999 m_c13_gone m_c13_squeezed
  m_c16_empty m_c16_garbage m_c17_inject m_c17_more m_c18_pattern m_c18_regexpath m_c14_many m_c14_nocommas
  m_c14_tenth m_c14_nofiles m_c14_crlf"

t_C1() {
  local d out
  for d in good good-after-triage; do
    if [ "$d" = good ]; then set -- spec.md round.md; else set -- --after-triage spec.md round.md; fi
    out="$( (cd "$F/$d" && "$L" "$@" > "$TMP/c1.out" 2>/dev/null; echo "exit=$?"; wc -c < "$TMP/c1.out" | tr -d ' ') )"
    check "$d" "$out" "$(lines exit=0 0)"
  done
  # The pinned contents of good (How to run, fixtures).
  check "good args" "$(cat "$F/good/args")" "spec.md round.md"
  check "good-after-triage args" "$(cat "$F/good-after-triage/args")" "--after-triage spec.md round.md"
  check "good spec claims" "$(grep -E '^### C[0-9]+:' "$F/good/spec.md" | cut -d: -f1 | tr '\n' ' ')" "### C1 ### C2 ### C3 ### C4 "
  check "good spec removed" "$(grep -c '^- status: removed-' "$F/good/spec.md")" 1
  check "good verdict" "$(grep -c '^verdict: ' "$F/good/round.md")/$(grep -cx 'verdict: FINDINGS' "$F/good/round.md")" 1/1
  check "good sections" "$(grep -E '^### C[0-9]+ — ' "$F/good/round.md" | tr '\n' '|')" "### C1 — PASS|### C2 — PASS|### C4 — FAIL → F-1-1|"
  check "good coverage" "$(awk '/^## Coverage/{getline; print; exit}' "$F/good/round.md")" \
    "claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 12  deferred: 0"
  check "triaged differs only by triage line" \
    "$(diff "$F/good/round.md" "$F/good-after-triage/round.md" | grep -E '^[<>]')" "> - triage: loop"
}

t_C2() {
  local c out e got=""
  for c in r1 r2 r3 r4 r5 r6 r7; do
    out="$(cd "$F/$c" && "$L" $(cat args) 2>/dev/null)"
    e=$?
    got="$got$c exit=$e rules=$(printf '%s\n' "$out" | awk 'NF{print $1}' | sort -u | tr '\n' ' ')
"
    [ -n "$out" ] || bad "$c: no output"
    check "$c stdout = expected-stdout" "$(cd "$F/$c" && "$L" $(cat args) 2>/dev/null)" "$(cat "$F/$c/expected-stdout")"
    if [ "$c" = r6 ]; then
      grep -q -- '--after-triage' "$F/$c/args" || bad "r6 args lack --after-triage"
    else
      grep -q -- '--after-triage' "$F/$c/args" && bad "$c args contain --after-triage"
    fi
  done
  check "rules per case" "$got" "$(lines 'r1 exit=1 rules=R1 ' 'r2 exit=1 rules=R2 ' 'r3 exit=1 rules=R3 ' \
    'r4 exit=1 rules=R4 ' 'r5 exit=1 rules=R5 ' 'r6 exit=1 rules=R6 ' 'r7 exit=1 rules=R7 ')
"
}

t_C3() {
  check "from /" "$(cd / && bash "$REPO/tests/scripts.sh"; echo "exit=$?"; bash "$REPO/tests/lint.sh"; echo "exit=$?")" \
    "$(lines 'scripts ok' exit=0 'lint ok' exit=0)"
}

t_C4() {
  local m
  for m in m_c4_done m_c4_second m_c4_trailing m_c4_capital m_c4_nospace m_c4_none; do
    check "$m" "$(on good "$m" spec.md round.md)" "$(lines 'R1 verdict' exit=1)"
  done
}

t_C5() {
  check "(a) extra spec claim" "$(on good m_c5_extra spec.md round.md)" "$(lines 'R2 missing C5' exit=1)"
  check "(b) removed status dropped" "$(on good m_c5_unremoved spec.md round.md)" "$(lines 'R2 missing C3' exit=1)"
  check "(c) claim gone from spec" "$(on good m_c5_unknown spec.md round.md)" "$(lines 'R2 unknown C4' exit=1)"
}

t_C6() {
  local r3; r3="$(lines 'R3 C1 fuzzer 3' 'R3 C1 attacker 3' 'R3 C1 stranger 3' exit=1)"
  check "--min-attempts 4 first" "$(on good none --min-attempts 4 spec.md round.md)" "$r3"
  check "--min-attempts 4 last" "$(on good none spec.md round.md --min-attempts 4)" "$r3"
  check "--min-attempts 4 between" "$(on good none spec.md --min-attempts 4 round.md)" "$r3"
  check "--min-attempts 3" "$(on good none --min-attempts 3 spec.md round.md)" exit=0
  check "--min-attempts 1" "$(on good none --min-attempts 1 spec.md round.md)" exit=0
  check "--min-attempts 4 with --after-triage" "$(on good-after-triage none --min-attempts 4 --after-triage spec.md round.md)" "$r3"
}

t_C7() {
  check "(a) ux dropped" "$(on good m_c7_noux spec.md round.md)" \
    "$(lines 'R3 C2 fuzzer 1' 'R3 C2 attacker 1' 'R3 C2 stranger 1' exit=1)"
  check "(b) extra persona" "$(on good m_c7_critic spec.md round.md)" "$(lines 'R3 C1 critic 0' 'R3 C2 critic 0' exit=1)"
}

t_C8() {
  check "(a) FAIL without finding" "$(on good m_c8_nofinding spec.md round.md)" "$(lines 'R4 no finding: ### C4 — FAIL' exit=1)"
  check "(b) finding without repro" "$(on good m_c8_norepro spec.md round.md)" "$(lines 'R4 no repro: F-1-1' exit=1)"
  check "UNVERIFIABLE with reason passes" "$(on good m_c8_reason spec.md round.md)" exit=0
  check "pointer to a missing finding" "$(on good m_c8_dangling spec.md round.md)" "$(lines 'R4 no repro: F-1-99' exit=1)"
}

t_C9() {
  check "(a) path outside entry points" "$(on good m_c9_outside spec.md round.md)" "$(lines 'R5 lib/internal.c' exit=1)"
  check "(b) exempt paths" "$(on good m_c9_exempt spec.md round.md)" exit=0
}

m_c10_clean()    { sed -i 's/^verdict: FINDINGS$/verdict: CLEAN/' round.md; }
m_c11_a()        { sed -i 's/^- triage: loop$/- triage: deferred → X-9/; s/^verdict: FINDINGS$/verdict: CLEAN/; s/deferred: 0$/deferred: 1/' round.md; }
m_c11_b()        { m_c11_a; sed -i 's/^## Spec-level findings$/## Spec-level findings\n### F-1-2  fingerprint: spec-x  repeat-of: none  personas: stranger\n- claim: spec\n- repro: read the spec\n- triage: loop/' round.md; }
m_c11_c()        { sed -i -E 's/^### (C[0-9]+) — (PASS|FAIL)( → F-1-1)?$/### \1 — UNVERIFIABLE → F-1-1/; s/^claims: .*/claims: 3  pass: 0  fail: 0  unverifiable: 3  attempts: 12  deferred: 0/' round.md; }
m_c11_c2()       { m_c11_c; sed -i 's/^verdict: FINDINGS$/verdict: BLOCKED/' round.md; }
m_c11_d()        { sed -i 's/^- triage: loop$/- triage: deferred → X-9/; s/deferred: 0$/deferred: 1/' round.md; }
# one of three claims UNVERIFIABLE, its only finding deferred, no spec-level
# finding: the UNVERIFIABLE count alone must keep R6 off CLEAN (and off BLOCKED).
m_c11_partunv()  { sed -i 's/^### C4 — FAIL → F-1-1$/### C4 — UNVERIFIABLE → F-1-1/; s/^- triage: loop$/- triage: deferred → X-9/; s/^verdict: FINDINGS$/verdict: CLEAN/; s/^claims: .*/claims: 3  pass: 2  fail: 0  unverifiable: 1  attempts: 12  deferred: 1/' round.md; }
m_c11_partunv2() { m_c11_partunv; sed -i 's/^verdict: CLEAN$/verdict: FINDINGS/' round.md; }
m_c11_partunv3() { m_c11_partunv; sed -i 's/^verdict: CLEAN$/verdict: BLOCKED/' round.md; }
m_c11_noclaims() {
  awk '/^## Claims/{print; skip=1; next} /^## Spec-level findings/{skip=0} skip && /^## Findings/{print; next} !skip' round.md > r.tmp && mv r.tmp round.md
  sed -i 's/^verdict: FINDINGS$/verdict: CLEAN/' round.md
}
m_c11_specdef()  {
  m_c11_a
  sed -i 's/^## Spec-level findings$/## Spec-level findings\n### F-1-2  fingerprint: spec-x  repeat-of: none  personas: stranger\n- claim: spec\n- repro: read the spec\n- triage: deferred → X-10/; s/deferred: 1$/deferred: 2/' round.md
}

t_C10() {
  check "(a) CLEAN with a loop finding" "$(on good-after-triage m_c10_clean --after-triage spec.md round.md)" \
    "$(lines 'R6 want FINDINGS have CLEAN' exit=1)"
  check "(b) R7 still checked" "$(on good-after-triage m_c13_999 --after-triage spec.md round.md)" \
    "$(lines 'R7 want [claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 12  deferred: 0] have [claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 999  deferred: 0]' exit=1)"
  check "R1 still checked" "$(on good-after-triage m_c4_done --after-triage spec.md round.md)" \
    "$(lines 'R1 verdict' 'R6 want FINDINGS have DONE' exit=1)"
}

t_C11() {
  check "(a) only finding deferred" "$(on good-after-triage m_c11_a --after-triage spec.md round.md)" exit=0
  check "(b) spec-level finding" "$(on good-after-triage m_c11_b --after-triage spec.md round.md)" \
    "$(lines 'R6 want FINDINGS have CLEAN' exit=1)"
  check "(c) all UNVERIFIABLE, FINDINGS" "$(on good-after-triage m_c11_c --after-triage spec.md round.md)" \
    "$(lines 'R6 want BLOCKED have FINDINGS' exit=1)"
  check "(c) all UNVERIFIABLE, BLOCKED" "$(on good-after-triage m_c11_c2 --after-triage spec.md round.md)" exit=0
  check "(d) deferred only, FINDINGS" "$(on good-after-triage m_c11_d --after-triage spec.md round.md)" \
    "$(lines 'R6 want CLEAN have FINDINGS' exit=1)"
  local out
  out="$(on good-after-triage m_c11_noclaims --after-triage spec.md round.md)"
  printf '%s\n' "$out" | grep -q '^R6' && bad "no claims, CLEAN: unexpected R6 line: $out"
  check "no claims: last line" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
  check "deferred spec-level finding still counts" "$(on good-after-triage m_c11_specdef --after-triage spec.md round.md)" \
    "$(lines 'R6 want FINDINGS have CLEAN' exit=1)"
  check "some UNVERIFIABLE, no loop, CLEAN" "$(on good-after-triage m_c11_partunv --after-triage spec.md round.md)" \
    "$(lines 'R6 want FINDINGS have CLEAN' exit=1)"
  check "some UNVERIFIABLE, no loop, FINDINGS" "$(on good-after-triage m_c11_partunv2 --after-triage spec.md round.md)" exit=0
  check "some UNVERIFIABLE, no loop, BLOCKED" "$(on good-after-triage m_c11_partunv3 --after-triage spec.md round.md)" \
    "$(lines 'R6 want FINDINGS have BLOCKED' exit=1)"
}

t_C12() {
  check "r6 in default mode" "$(lint_in "$F/r6" spec.md round.md)" exit=0
  check "triaged CLEAN in default mode" "$(on good-after-triage m_c10_clean spec.md round.md)" exit=0
}

t_C13() {
  check "wrong count" "$(on good m_c13_999 spec.md round.md)" \
    "$(lines 'R7 want [claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 12  deferred: 0] have [claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 999  deferred: 0]' exit=1)"
  check "no Coverage" "$(on good m_c13_gone spec.md round.md)" \
    "$(lines 'R7 want [claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 12  deferred: 0] have []' exit=1)"
  check "single spaces" "$(on good m_c13_squeezed spec.md round.md)" exit=0
}

# same_as_oracle <dir>: default-mode output of the script equals the old
# inline block's, and the exit is 1 exactly when the oracle printed.
same_as_oracle() {
  local d="$1" label="$2" old new e
  old="$(cd "$d" && S=spec.md R=round.md T="$(mktemp -d "$TMP/t.XXXXXX")" bash "$OLD" 2>/dev/null)"
  new="$(cd "$d" && "$L" spec.md round.md 2>/dev/null)"
  e=$?
  check "$label: stdout vs oracle" "$new" "$old"
  if [ -n "$old" ]; then [ "$e" = 1 ] || bad "$label: exit $e, oracle printed"; else [ "$e" = 0 ] || bad "$label: exit $e, oracle silent"; fi
}

t_C14() {
  if ! git -C "$REPO" cat-file -e "$BASE:skills/adversarial-review/SKILL.md" 2>/dev/null; then
    bad "base $BASE not in history: fetch it to build the oracle"
    return
  fi
  OLD="$TMP/old.sh"
  git -C "$REPO" show "$BASE:skills/adversarial-review/SKILL.md" | awk '/^### 5\. /{p=1} /^### 6\. /{p=0} p' \
    | awk '/^```bash/{f=1;next} /^```/{f=0} f' > "$OLD"
  [ -s "$OLD" ] || { bad "oracle is empty"; return; }
  local c m w loc
  for loc in C C.UTF-8 ""; do
    for c in "$F"/*/; do
      w="$(work "$(basename "$c")")"
      LC_ALL="$loc" same_as_oracle "$w" "${loc:-unset}/$(basename "$c")"
    done
    for m in $DEFAULT_MUTATIONS; do
      w="$(work good)"
      ( cd "$w" && "$m" ) || { bad "mutation $m failed"; continue; }
      LC_ALL="$loc" same_as_oracle "$w" "${loc:-unset}/$m"
    done
  done
}

t_C15() {
  local w i n
  w="$(work good)"
  local -a runs=(
    ""
    "spec.md"
    "spec.md round.md extra.md"
    "nosuch.md round.md"
    "spec.md nosuch.md"
    ". round.md"
    "--bogus spec.md round.md"
    "--min-attempts 0 spec.md round.md"
    "--min-attempts abc spec.md round.md"
    "--min-attempts -1 spec.md round.md"
    "--min-attempts 3x spec.md round.md"
    "spec.md round.md --min-attempts"
    # Beyond the spec's list: other words starting with "-" are bad usage.
    "--min-attempts=4 spec.md round.md"
    "-- spec.md round.md"
    "spec.md round.md -"
    "--after-triage --after-triage spec.md round.md"
    "-h"
    "--min-attempts 4 --min-attempts 4 spec.md round.md"
  )
  n=0
  for i in "${runs[@]}"; do
    n=$((n + 1))
    ( cd "$w" && set -f && "$L" $i > "$TMP/o" 2> "$TMP/e"; echo $? > "$TMP/x" )
    check "run $n [$i]" "exit=$(cat "$TMP/x") out=$(wc -c < "$TMP/o" | tr -d ' ') err=$([ -s "$TMP/e" ] && echo yes || echo no)" \
      "exit=2 out=0 err=yes"
    case "$i" in
      nosuch.md*|*nosuch.md) grep -qF nosuch.md "$TMP/e" || bad "run $n: stderr does not name nosuch.md: $(cat "$TMP/e")" ;;
    esac
  done
  # A dash word in a path's place is bad usage even when such a file exists.
  cp "$w/spec.md" "$w/-s.md"
  ( cd "$w" && "$L" -s.md round.md > "$TMP/o" 2> "$TMP/e"; echo $? > "$TMP/x" )
  check "existing file named -s.md" "exit=$(cat "$TMP/x") out=$(wc -c < "$TMP/o" | tr -d ' ')" "exit=2 out=0"
  rm -f "$w/-s.md"
  # An empty option value, a fifo and /dev/null as the report.
  ( cd "$w" && "$L" --min-attempts '' spec.md round.md > "$TMP/o" 2>/dev/null; echo $? > "$TMP/x" )
  check "--min-attempts ''" "exit=$(cat "$TMP/x") out=$(wc -c < "$TMP/o" | tr -d ' ')" "exit=2 out=0"
  mkfifo "$w/fifo.md"
  ( cd "$w" && timeout 10 "$L" spec.md fifo.md > "$TMP/o" 2>/dev/null; echo $? > "$TMP/x" )
  case "$(cat "$TMP/x")" in 1|2) ;; *) bad "fifo as round.md: exit $(cat "$TMP/x")" ;; esac
  ( cd "$w" && "$L" spec.md /dev/null > "$TMP/o" 2>/dev/null; echo $? > "$TMP/x" )
  case "$(cat "$TMP/x")" in 1|2) ;; *) bad "/dev/null as round.md: exit $(cat "$TMP/x")" ;; esac
  # A path that is a directory, given as round.md.
  ( cd "$w" && "$L" spec.md / > "$TMP/o" 2>/dev/null; echo $? > "$TMP/x" )
  check "directory as round.md" "exit=$(cat "$TMP/x") out=$(wc -c < "$TMP/o" | tr -d ' ')" "exit=2 out=0"
}

t_C16() {
  check "(a) empty report" "$(on good m_c16_empty spec.md round.md)" \
    "$(lines 'R1 verdict' 'R2 missing C1' 'R2 missing C2' 'R2 missing C4' \
      'R7 want [claims: 0  pass: 0  fail: 0  unverifiable: 0  attempts: 0  deferred: 0] have []' exit=1)"
  local out k
  for k in 1 2 3; do
    out="$(on good m_c16_garbage spec.md round.md)"
    check "(b) garbage #$k: first line" "$(printf '%s\n' "$out" | head -n 1 | cut -c1-2)" R1
    check "(b) garbage #$k: exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
  done
  out="$(on good m_c16_nospec spec.md round.md)"
  for k in 'R2 unknown C1' 'R2 unknown C2' 'R2 unknown C4'; do
    printf '%s\n' "$out" | grep -qxF "$k" || bad "(c) empty spec: no line [$k]"
  done
  check "(c) empty spec: exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
  out="$(on good m_c16_empty --after-triage spec.md round.md)"
  check "(a) empty report after triage: exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
}

t_C17() {
  local w out m
  w="$(work good)"
  ( cd "$w" && m_c17_inject )
  out="$(lint_in "$w" spec.md round.md)"
  check "stdout" "$out" "$(lines 'R3 C1 $(touch${IFS}pwned3) 0' 'R3 C2 $(touch${IFS}pwned3) 0' \
    'R5 $(touch${IFS}pwned).c' 'R5 *.c' 'R5 -rf.c' exit=1)"
  for m in pwned pwned3; do [ -e "$w/$m" ] && bad "marker $m exists"; done
  out="$(lint_in "$w" --after-triage spec.md round.md)"
  for m in pwned pwned3; do [ -e "$w/$m" ] && bad "after-triage: marker $m exists"; done
  # Backticks, semicolons, quotes and % are printed verbatim and never run.
  w="$(work good)"
  ( cd "$w" && m_c17_more )
  out="$(lint_in "$w" spec.md round.md)"
  check "verbatim" "$out" "$(lines 'R3 C1 "q%s" 0' 'R3 C2 "q%s" 0' 'R5 `touch${IFS}pwned4`.c' 'R5 ;touch${IFS}pwned5;.c' 'R5 "q%s".c' exit=1)"
  for m in pwned4 pwned5; do [ -e "$w/$m" ] && bad "marker $m exists"; done
  check "work dir" "$(ls -A "$w" | tr '\n' ' ')" "round.md spec.md "
  # A 200000-byte path (longer than one exec argument may be) still fails R5.
  local long
  long="$(head -c 200000 /dev/zero | tr '\0' a).c"
  w="$(work good)"
  printf '%s\n' "## Files opened" "$long" > "$TMP/files"
  ( cd "$w" && sed -i "/^## Files opened$/{r $TMP/files
d}" round.md )
  check "very long path" "$(lint_in "$w" spec.md round.md)" "$(lines "R5 $long" exit=1)"
}

t_C18() {
  check "pattern entry points" "$(on good m_c18_pattern spec.md round.md)" "$(lines 'R5 lib/internal.c' exit=1)"
  # The opened path is fixed text too: as a regex it would match bin/tool.c.
  check "pattern opened paths" "$(on good m_c18_regexpath spec.md round.md)" "$(lines 'R5 bin/too..c' 'R5 [b]in/tool.c' exit=1)"
}

t_C19() {
  local w B TT c
  w="$(work good)"
  B="$TMP/c19.sha"
  TT="$(mktemp -d "$TMP/tt.XXXXXX")"
  ( cd "$w" && sha256sum spec.md round.md > "$B"
    TMPDIR=$TT "$L" spec.md round.md
    TMPDIR=$TT "$L" --after-triage spec.md round.md
    TMPDIR=$TT "$L" nosuch.md round.md
    TMPDIR=$TT "$L" --min-attempts 4 spec.md round.md ) > /dev/null 2>&1
  check "temp dir count" "$(ls -A "$TT" | wc -l | tr -d ' ')" 0
  check "work dir" "$(ls -A "$w" | tr '\n' ' ')" "round.md spec.md "
  check "inputs" "$(cd "$w" && sha256sum -c --quiet "$B" && echo unchanged)" unchanged
  for c in r2 r5 good; do
    ( cd "$F/$c" && TMPDIR=/nonexistent/x "$L" $(cat args) > /dev/null 2>&1; echo $? ) > "$TMP/x"
    case "$(cat "$TMP/x")" in 1|2) ;; *) bad "$c with TMPDIR=/nonexistent/x: exit $(cat "$TMP/x")" ;; esac
  done
  # The fixture dirs stay as checked in.
  check "fixtures untouched" "$(git -C "$REPO" status --porcelain -- tests/fixtures)" ""
}

t_C20() {
  local D
  D="$(mktemp -d "$TMP/s.XXXXXX")/my dir"
  mkdir -p "$D"
  cp "$F/good/spec.md" "$F/good/round.md" "$D/"
  check "spaces, from /" "$(cd / && { "$L" "$D/spec.md" "$D/round.md" 2>/dev/null; echo "exit=$?"; })" exit=0
  sed -i 's/^verdict: FINDINGS$/verdict: X/' "$D/round.md"
  check "spaces, bad verdict" "$(cd / && { "$L" "$D/spec.md" "$D/round.md" 2>/dev/null; echo "exit=$?"; })" "$(lines 'R1 verdict' exit=1)"
  check "relative path from a parent dir" "$(cd "$D/.." && { "$L" "my dir/spec.md" "my dir/round.md" 2>/dev/null; echo "exit=$?"; })" "$(lines 'R1 verdict' exit=1)"
}

t_C21() {
  check "no awk/grep/comm/sed in steps 5-6 code" \
    "$(awk '/^### 5\. /{p=1} /^### 7\. /{p=0} p' "$M" | awk '/^```/{f=!f; next} f' | grep -cE '(^|[^[:alnum:]_-])(awk|grep|comm|sed)([^[:alnum:]_-]|$)')" 0
  check "old rule text gone" "$(grep -cE 'comm -2|min=3|R4 no repro|R2 missing' "$M")" 0
  atleast "step 5 calls the script" "$(awk '/^### 5\. /{p=1} /^### 6\. /{p=0} p' "$M" | grep -c 'scripts/lint-report.sh')" 1
  atleast "step 6 calls --after-triage" "$(awk '/^### 6\. /{p=1} /^### 7\. /{p=0} p' "$M" | grep -cE 'scripts/lint-report\.sh"? --after-triage')" 1
  local n; n="$(wc -l < "$M")"
  [ "$n" -lt 500 ] || bad "SKILL.md has $n lines"
  atleast "SKILL_DIR defined" "$(awk '/^Variables used below/{p=1} /^$/{p=0} p' "$M" | grep -c 'SKILL_DIR')" 1
  check "single script path" \
    "$(awk '/^### 5\. /{p=1} /^### 7\. /{p=0} p' "$M" | grep -oE '[$A-Za-z0-9_/{}.-]*scripts/lint-report\.sh' | sort -u)" \
    '$SKILL_DIR/scripts/lint-report.sh'
  local h
  for h in '### 5. ' '### 6. ' '### 7. '; do grep -q "^$h" "$M" || bad "heading [$h] missing"; done
}

t_C22() {
  local C out
  for name in pipeline/scripts/broken.sh "adversarial-review/scripts/broken.sh" "pipeline/scripts/broken script.sh"; do
    C="$(repo_copy)"
    mkdir -p "$(dirname "$C/skills/$name")"
    printf '#!/usr/bin/env bash\nif then fi\n' > "$C/skills/$name"
    out="$(bash "$C/tests/lint.sh"; echo "exit=$?")"
    printf '%s\n' "$out" | grep -E '^FAIL:' | grep -F "skills/$name" | grep -qF 'does not parse' \
      || bad "$name: no parse FAIL line: $out"
    check "$name: last line" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
    printf '%s\n' "$out" | grep -qx 'lint ok' && bad "$name: lint ok printed"
  done
}

t_C23() {
  local C out s
  for s in a b; do
    C="$(repo_copy)"
    if [ "$s" = a ]; then
      echo 1 > "$C/tests/fixtures/lint-report/good/expected-exit"; want=lint-report/good
    else
      printf 'R1 verdict \n' > "$C/tests/fixtures/lint-report/r1/expected-stdout"; want=lint-report/r1
    fi
    out="$(bash "$C/tests/scripts.sh"; echo "exit=$?")"
    printf '%s\n' "$out" | grep -E '^FAIL:' | grep -qF "$want" || bad "($s) scripts.sh: no FAIL naming $want: $out"
    check "($s) scripts.sh exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
    printf '%s\n' "$out" | grep -qx 'scripts ok' && bad "($s) scripts.sh printed scripts ok"
    out="$(bash "$C/tests/lint.sh"; echo "exit=$?")"
    printf '%s\n' "$out" | grep -E '^FAIL:' | grep -qF "$want" || bad "($s) lint.sh: no FAIL naming $want: $out"
    check "($s) lint.sh exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
    printf '%s\n' "$out" | grep -qxE 'lint ok|scripts ok' && bad "($s) lint.sh printed an ok line: $out"
    check "($s) lint.sh relays each scripts.sh FAIL line" \
      "$(printf '%s\n' "$out" | grep -c '^FAIL:')" "$(bash "$C/tests/scripts.sh" | grep -c '^FAIL:')"
  done
}

# scripts_fails <setup fn> <text>: on a fresh copy, scripts.sh prints a FAIL
# line containing <text> and exits 1.
scripts_fails() {
  local C out
  C="$(repo_copy)"
  ( cd "$C" && "$1" ) || { bad "setup $1 failed"; return; }
  out="$(bash "$C/tests/scripts.sh"; echo "exit=$?")"
  printf '%s\n' "$out" | grep -E '^FAIL:' | grep -qF -- "$2" || bad "$1: no FAIL line naming [$2]: $out"
  check "$1 exit" "$(printf '%s\n' "$out" | tail -n 1)" exit=1
}
s_no_stdout()   { rm tests/fixtures/lint-report/r2/expected-stdout; }
s_no_args()     { rm tests/fixtures/lint-report/r2/args; }
s_no_exit()     { rm tests/fixtures/lint-report/r2/expected-exit; }
s_orphan()      { mkdir -p tests/fixtures/nosuch/x && cp tests/fixtures/lint-report/good/* tests/fixtures/nosuch/x/; }
s_untested()    { printf '#!/usr/bin/env bash\nexit 0\n' > skills/adversarial-review/scripts/extra.sh; chmod +x skills/adversarial-review/scripts/extra.sh; }
s_empty_args()  { : > tests/fixtures/lint-report/good/args; }
s_abc_exit()    { echo abc > tests/fixtures/lint-report/r2/expected-exit; }
s_empty_case()  { mkdir tests/fixtures/lint-report/zz-empty; }
s_dup()         { mkdir -p skills/pipeline/scripts && cp skills/adversarial-review/scripts/lint-report.sh skills/pipeline/scripts/; }
s_negative_exit() { echo -1 > tests/fixtures/lint-report/r2/expected-exit; }

t_C24() {
  scripts_fails s_no_stdout lint-report/r2
  scripts_fails s_no_args lint-report/r2
  scripts_fails s_no_exit lint-report/r2
  scripts_fails s_orphan nosuch
  scripts_fails s_untested extra.sh
  scripts_fails s_empty_args lint-report/good
  scripts_fails s_abc_exit lint-report/r2
  scripts_fails s_negative_exit lint-report/r2
  scripts_fails s_empty_case lint-report/zz-empty
  scripts_fails s_dup skills/pipeline/scripts/lint-report.sh
  scripts_fails s_dup skills/adversarial-review/scripts/lint-report.sh
  # A regular file directly under the fixture dir is ignored.
  local C
  C="$(repo_copy)"
  echo note > "$C/tests/fixtures/lint-report/README"
  check "stray regular file" "$(bash "$C/tests/scripts.sh"; echo "exit=$?")" "$(lines 'scripts ok' exit=0)"
  # args words are never glob-expanded.
  C="$(repo_copy)"
  echo '*.md' > "$C/tests/fixtures/lint-report/usage-bad-option/args"
  check "args not glob-expanded" "$(bash "$C/tests/scripts.sh"; echo "exit=$?")" "$(lines 'scripts ok' exit=0)"
}

t_C25() {
  local C
  C="$(repo_copy)"
  rm -rf "$C"/skills/*/scripts "$C/tests/fixtures"
  check "no scripts, no fixtures" "$(bash "$C/tests/scripts.sh"; echo "exit=$?"; bash "$C/tests/lint.sh"; echo "exit=$?")" \
    "$(lines 'scripts ok' exit=0 'lint ok' exit=0)"
}

t_C26() {
  check "modes" "$(git -C "$REPO" ls-files -s skills/adversarial-review/scripts/lint-report.sh tests/scripts.sh | cut -c1-6)" \
    "$(lines 100755 100755)"
  check "shebangs" "$(head -qn1 "$L" "$REPO/tests/scripts.sh")" "$(lines '#!/usr/bin/env bash' '#!/usr/bin/env bash')"
}

t_C27() {
  ( cd "$REPO"
    atleast "README jq" "$(sed -n '/^Requirements:/,/^$/p' README.md | grep -c '`jq`')" 1
    atleast "README scripts.sh" "$(awk '/^## Lints and the toy repo/{p=1;next} /^## /{p=0} p' README.md | grep -c 'tests/scripts.sh')" 1
    atleast "README fixtures" "$(awk '/^## Lints and the toy repo/{p=1;next} /^## /{p=0} p' README.md | grep -c 'tests/fixtures/')" 1
    atleast "report-template script" "$(grep -c 'scripts/lint-report.sh' skills/adversarial-review/references/report-template.md)" 1
    [ "$fail" = 0 ] ) || fail=1
}

t_C28() {
  atleast "step 6 R6 want" "$(awk '/^### 6\. /{p=1} /^### 7\. /{p=0} p' "$M" | grep -c 'R6 want')" 1
  atleast "steps 4-6 R7 want" "$(awk '/^### 4\. /{p=1} /^### 7\. /{p=0} p' "$M" | grep -c 'R7 want')" 1
  check "never re-prompts" "$(awk '/^### 5\. /{p=1} /^### 7\. /{p=0} p' "$M" | tr '\n' ' ' | tr -s ' ' | grep -cF 'never re-prompts a persona')" 1
  check "no step-5 formula" "$(grep -c 'step-5 formula' "$M")" 0
}

t_C29() {
  check "old output rule gone" "$(grep -c 'any output is a failure' "$M")" 0
  check "other exit sentence" "$(awk '/^### 5\. /{p=1} /^### 6\. /{p=0} p' "$M" | tr '\n' ' ' | tr -s ' ' \
    | grep -cF 'Any other exit: stop the round and report stderr; never a pass, never INVALID.')" 1
  check "exit 0/1 sentence" "$(awk '/^### 5\. /{p=1} /^### 6\. /{p=0} p' "$M" | tr '\n' ' ' | tr -s ' ' \
    | grep -cF 'Exit 0: pass. Exit 1: lint failure.')" 1
}

t_C30() {
  local FL s
  FL="$(tr '\n' ' ' < "$M" | tr -s ' ')"
  for s in 'find the persona at fault' 'Re-prompt that persona **once**' '- relint: <rule numbers and the failing lines>' \
    '- draft: <its existing report path>' 'skip step 6, continue at step 7' 'Two INVALID rounds in a row trip the valve'; do
    check "[$s]" "$(printf '%s\n' "$FL" | grep -cF -- "$s")" 1
  done
  atleast "verdict: INVALID line" "$(grep -cx 'verdict: INVALID' "$M")" 1
  atleast "lint: header example" "$(grep -cE '^lint: R3 C2 attacker 1; R5 ' "$M")" 1
}

t_C31() {
  if ! git -C "$REPO" cat-file -e "$BASE" 2>/dev/null; then bad "base $BASE not in history"; return; fi
  check "files outside the area" "$(git -C "$REPO" diff --name-only "$BASE"...HEAD | grep -cvE '^(skills/adversarial-review/|tests/|README\.md$)')" 0
  check "untouchable files" "$(git -C "$REPO" diff --name-only "$BASE"...HEAD -- tests/toy-repo.sh skills/adversarial-review/agents/ \
    skills/adversarial-review/references/triage.md skills/adversarial-review/references/attack-catalogue.md | wc -l | tr -d ' ')" 0
  check "report-template rule lines" "$(git -C "$REPO" diff "$BASE"...HEAD -- skills/adversarial-review/references/report-template.md \
    | grep -cE '^-[1-7]\. |^-   ')" 0
}

all="C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 C21 C22 C23 C24 C25 C26 C27 C28 C29 C30 C31"
[ $# -gt 0 ] && all="$*"
for cur in $all; do
  if ! declare -F "t_$cur" > /dev/null; then
    bad "no such claim"
    continue
  fi
  before=$fail
  fail=0
  "t_$cur"
  [ "$fail" = 0 ] && echo "ok $cur"
  [ "$before" = 0 ] || fail=1
done

if [ "$fail" -eq 0 ]; then
  echo "claims ok"
  exit 0
fi
exit 1
