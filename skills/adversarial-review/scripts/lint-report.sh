#!/usr/bin/env bash
# Lint a merged verification report (round-N.md) against its spec.md.
# The rules are the "Lint" list in references/report-template.md.
#
#   lint-report.sh [--after-triage] [--min-attempts N] <spec.md> <round.md>
#
# Default mode checks rules 1-5 and 7 (step 5); --after-triage checks all
# of 1-7 (step 6). --min-attempts defaults to 3; type: ux claims need 1.
# Prints one "R<n> ..." line per failure. Exit 0: clean. Exit 1: lint
# failure. Exit 2: bad usage, unreadable input, or a rule that could not run
# (a missing or failing program); stdout is then empty. Writes no files.
set -uo pipefail

usage() {
  echo "usage: lint-report.sh [--after-triage] [--min-attempts N] <spec.md> <round.md>" >&2
  exit 2
}

after=0
min=""
S=""
R=""
npos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --after-triage)
      [ "$after" = 0 ] || usage
      after=1
      ;;
    --min-attempts)
      [ $# -ge 2 ] && [ -z "$min" ] || usage
      case "$2" in
        ''|0*|*[!0-9]*) usage ;;
      esac
      min="$2"
      shift
      ;;
    -*) usage ;;
    *)
      npos=$((npos + 1))
      case "$npos" in
        1) S="$1" ;;
        2) R="$1" ;;
        *) usage ;;
      esac
      ;;
  esac
  shift
done
[ "$npos" = 2 ] || usage
[ -n "$min" ] || min=3

for f in "$S" "$R"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "lint-report.sh: not a readable file: $f" >&2
    exit 2
  fi
done

# Every program a rule runs must exist: a missing one would turn a rule's
# input into nothing and could pass a bad report.
for t in awk grep sed sort comm tr wc; do
  command -v "$t" >/dev/null 2>&1 || { echo "lint-report.sh: missing program: $t" >&2; exit 2; }
done

# A rule that cannot run (a program fails, an argument is too long for it)
# stops the run with 2. rules runs in a subshell, so this exits that
# subshell with 2 and the caller below stops with 2 and prints nothing.
norun() { echo "lint-report.sh: rule $1 could not run" >&2; exit 2; }
# grep and grep -c exit 1 when nothing matches; only 2 and above is an error.
nomatch() { [ "$1" -le 1 ] || norun "$2"; }
# The lists live in variables, not temp files, so an interrupted run leaves
# nothing behind. lines prints a list back with one line per entry, and
# nothing for an empty list.
lines() { [ -z "$1" ] || printf '%s\n' "$1"; }

# The rule bodies below are the inline step-5 block from SKILL.md as it was
# (adversarial-review SKILL.md step 5 at 18e2a1a), with min=3 replaced by the
# option, temp files replaced by variables, and every exit status checked.
# Keep regexes and output text unchanged: the skill and the fixtures depend
# on them byte for byte.
rules() {
# R1 verdict line
n=$(grep -cE '^verdict: (CLEAN|SHIP|FINDINGS|BLOCKED)$' "$R"); nomatch $? R1
[ "$n" = 1 ] || echo "R1 verdict"

# R2 every live spec claim has a verdict
claims=$(awk '/^### C[0-9]+:/{c=$2; sub(/:$/,"",c); ids[c]=1} /^- status: removed-/{rm[c]=1}
     END{for(i in ids) if(!rm[i]) print i}' "$S" | sort) || norun R2
verdicts=$({ grep -oE '^### C[0-9]+ — (PASS|FAIL|UNVERIFIABLE)' "$R" || [ $? = 1 ]; } | awk '{print $2}' | sort) || norun R2
comm -23 <(lines "$claims") <(lines "$verdicts") | sed 's/^/R2 missing /' || norun R2
comm -13 <(lines "$claims") <(lines "$verdicts") | sed 's/^/R2 unknown /' || norun R2

# R3 every PASS has min attempts under each persona (1 for type: ux)
PERSONAS=$(sed -n 's/^personas: *//p' "$R" | tr -d ',') || norun R3
awk -v min="$min" -v personas="$PERSONAS" '
  BEGIN{n=split(personas,P," ")}
  FNR==NR { if(/^### C[0-9]+:/){c=$2; sub(/:$/,"",c)} if(/^- type: ux/) ux[c]=1; next }
  /^### C[0-9]+ — PASS/{flush(); claim=$2; inpass=1; next}
  /^### /{flush(); inpass=0}
  inpass && /^- attempts \(/{cur=$0; sub(/.*\(/,"",cur); sub(/\).*/,"",cur); next}
  inpass && /^  [0-9]+\. /{cnt[cur]++}
  END{flush()}
  function flush(){ if(claim=="") return; m=(claim in ux)?1:min
    for(i=1;i<=n;i++) if(cnt[P[i]]+0<m) print "R3", claim, P[i], cnt[P[i]]+0
    split("",cnt); claim="" }' "$S" "$R" || norun R3

# R4 every FAIL/UNVERIFIABLE points at a finding that has repro: or reason:
{ grep -E '^### C[0-9]+ — (FAIL|UNVERIFIABLE)' "$R" || [ $? = 1 ]; } \
  | { grep -vE '→ F-[0-9]+-[0-9]+' || [ $? = 1 ]; } | sed 's/^/R4 no finding: /' || norun R4
need=$({ grep -oE '^### C[0-9]+ — (FAIL|UNVERIFIABLE) → F-[0-9]+-[0-9]+' "$R" || [ $? = 1 ]; } | awk '{print $NF}' | sort -u) || norun R4
have=$(awk '/^### F-[0-9]+-[0-9]+ /{f=$2} /^- (repro|reason):/{if(f) ok[f]=1} END{for(k in ok) print k}' "$R" | sort -u) || norun R4
comm -23 <(lines "$need") <(lines "$have") | sed 's/^/R4 no repro: /' || norun R4

# R5 no repo source path in Files opened outside Entry points. Repo files are
# listed relative to repo_root; scratch payloads and scripts are absolute
# (or under $HOME) and are the verifier's own, so they are not checked.
entry=$(awk '/^## Entry points/{p=1;next} /^## /{p=0} p' "$S") || norun R5
awk '/^## Files opened/{p=1;next} /^## /{p=0} p' "$R" \
  | { grep -oE '[^ ]+\.(java|kt|ts|tsx|js|py|go|rs|rb|cs|swift|scala|c|cpp|h)$' || [ $? = 1 ]; } \
  | { grep -vE '^(/|\$HOME|~)' || [ $? = 1 ]; } \
  | awk 'FILENAME == ARGV[1] { e[++n] = $0; next }
         { for (i = 1; i <= n; i++) if (index(e[i], $0)) next; print "R5 " $0 }' \
      <(lines "$entry") - || norun R5

# R6 triage words and header verdict after triage (--after-triage only).
# Every ### F- block under ## Findings and ## Spec-level findings is
# classified from its own fields. It blocks when its severity is not low or
# medium (high, empty, missing or misspelt), its category is not one of
# implementation-bug, spec-gap or env (security, or anything unrecognised),
# its claim is neither "spec" nor a claim id in spec.md, or it is medium on a
# type: security claim; a severity, category or claim line given twice also
# blocks. A blocking finding wants "- triage: loop" whatever its triage line
# says. A non-blocking finding under ## Findings whose triage word is
# "deferred" and whose claim is not type: security is skipped. Every other
# finding wants "known". One "R6 triage <id> want <w> have <h>" line per
# finding whose first triage word differs ("none" when there is none), in
# file order. Then the verdict: BLOCKED when there is at least one claim
# section and every one is UNVERIFIABLE; else FINDINGS when a finding blocks
# or a claim is UNVERIFIABLE; else SHIP when a finding is known; else CLEAN.
if [ "$after" = 1 ]; then
  r6=$(awk '
    function val(k,   v) { v = $0; sub("^- " k ":[ \t]*", "", v); sub(/[ \t\r]+$/, "", v); return v }
    function setf(k, v) { if (k in fv) fv[k] = "\001"; else fv[k] = v }
    function flush(   sev, cat, cl, ty, blocks) {
      if (id == "") return
      sev = ("severity" in fv) ? fv["severity"] : ""
      cat = ("category" in fv) ? fv["category"] : ""
      cl = ("claim" in fv) ? fv["claim"] : ""
      ty = (cl in type) ? type[cl] : ""
      blocks = (sev != "low" && sev != "medium") ||
        (cat != "implementation-bug" && cat != "spec-gap" && cat != "env") ||
        (cl != "spec" && !(cl in known)) ||
        (ty == "security" && sev == "medium")
      if (!blocks && tr == "deferred" && sec == "F" && ty != "security") { id = ""; return }
      w = blocks ? "loop" : "known"
      if (blocks) nb++; else nk++
      if (tr != w) out[++no] = "R6 triage " id " want " w " have " tr
      id = ""
    }
    FNR == NR {
      if (/^### C[0-9]+:/) { c = $2; sub(/:$/, "", c); known[c] = 1; next }
      if (/^#/) { c = ""; next }
      if (c != "" && !(c in type) && /^- type:/) type[c] = val("type")
      next
    }
    /^## / { flush(); sec = ($0 ~ /^## Findings/) ? "F" : (($0 ~ /^## Spec-level findings/) ? "S" : ""); next }
    /^### / { flush(); if (sec != "" && /^### F-/) { id = $2; tr = "none"; split("", fv) } next }
    id != "" && /^- (severity|category|claim):/ { k = $0; sub(/^- /, "", k); sub(/:.*/, "", k); setf(k, val(k)); next }
    id != "" && tr == "none" && /^- triage:/ { t = val("triage"); split(t, a, /[ \t]+/); if (a[1] != "") tr = a[1] }
    END { flush(); print nb + 0, nk + 0; for (i = 1; i <= no; i++) print out[i] }' "$S" "$R") || norun R6
  counts=$(printf '%s\n' "$r6" | sed -n 1p) || norun R6
  printf '%s\n' "$r6" | sed 1d || norun R6
  nblock=${counts% *}
  nknown=${counts#* }
  unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R"); nomatch $? R6
  claims=$(grep -cE '^### C[0-9]+ — (PASS|FAIL|UNVERIFIABLE)' "$R"); nomatch $? R6
  if [ "$claims" -gt 0 ] && [ "$unv" = "$claims" ]; then
    vwant=BLOCKED
  elif [ "$((nblock + unv))" -gt 0 ]; then
    vwant=FINDINGS
  elif [ "$nknown" -gt 0 ]; then
    vwant=SHIP
  else
    vwant=CLEAN
  fi
  vhave=$(awk '/^verdict: /{sub(/^verdict: /,""); print; exit}' "$R") || norun R6
  [ "$vwant" = "$vhave" ] || echo "R6 want $vwant have $vhave"
fi

# R7 coverage line matches the claim sections (re-run after step 6)
pass=$(grep -cE '^### C[0-9]+ — PASS' "$R"); nomatch $? R7
fail=$(grep -cE '^### C[0-9]+ — FAIL' "$R"); nomatch $? R7
unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R"); nomatch $? R7
att=$(awk '/^## Claims/{p=1} /^## Findings/{p=0} p && /^  [0-9]+\. /' "$R" | wc -l | tr -d ' ') || norun R7
def=$(grep -c '^- triage: deferred' "$R"); nomatch $? R7
want="claims: $((pass+fail+unv))  pass: $pass  fail: $fail  unverifiable: $unv  attempts: $att  deferred: $def"
have=$(awk '/^## Coverage/{getline; print; exit}' "$R") || norun R7
wsq=$(echo "$want" | tr -s ' ') || norun R7
hsq=$(echo "$have" | tr -s ' ') || norun R7
[ "$wsq" = "$hsq" ] || echo "R7 want [$want] have [$have]"
}

# Collect the lines first and print them only when every rule ran, so a
# rule that could not run gives exit 2 and nothing on stdout.
out="$(rules)" || exit 2
[ -n "$out" ] || exit 0
printf '%s\n' "$out"
exit 1
