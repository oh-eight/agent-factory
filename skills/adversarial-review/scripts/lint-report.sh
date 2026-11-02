#!/usr/bin/env bash
# Lint a merged verification report (round-N.md) against its spec.md.
# The rules are the "Lint" list in references/report-template.md.
#
#   lint-report.sh [--after-triage] [--min-attempts N] <spec.md> <round.md>
#
# Default mode checks rules 1-5 and 7 (step 5); --after-triage checks all
# of 1-7 (step 6). --min-attempts defaults to 3; type: ux claims need 1.
# Prints one "R<n> ..." line per failure. Exit 0: clean. Exit 1: lint
# failure. Exit 2: bad usage, unreadable input, or a read or write error
# on its temp files (fails closed). Writes nothing but a temp directory
# that it removes.
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

T="$(mktemp -d)" || { echo "lint-report.sh: cannot create a temp directory" >&2; exit 2; }
[ -n "$T" ] && [ -d "$T" ] || { echo "lint-report.sh: cannot create a temp directory" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

# A failed temp-file write (disk full, file size limit) must not turn into
# empty rule input and a silent pass. rules runs in a subshell, so this exits
# that subshell with 2 and the caller below stops with 2.
ioerr() { echo "lint-report.sh: I/O error on a temp file: $1" >&2; exit 2; }

# The rule bodies below are the inline step-5 block from SKILL.md as it was,
# with min=3 replaced by the option. Keep regexes and output text unchanged:
# the skill and the fixtures depend on them byte for byte.
rules() {
# R1 verdict line
[ "$(grep -cE '^verdict: (CLEAN|FINDINGS|BLOCKED)$' "$R")" = 1 ] || echo "R1 verdict"

# R2 every live spec claim has a verdict
awk '/^### C[0-9]+:/{c=$2; sub(/:$/,"",c); ids[c]=1} /^- status: removed-/{rm[c]=1}
     END{for(i in ids) if(!rm[i]) print i}' "$S" | sort > "$T/claims" || ioerr claims
{ grep -oE '^### C[0-9]+ — (PASS|FAIL|UNVERIFIABLE)' "$R" || [ $? = 1 ]; } | awk '{print $2}' | sort > "$T/verdicts" || ioerr verdicts
comm -23 "$T/claims" "$T/verdicts" | sed 's/^/R2 missing /' || ioerr claims
comm -13 "$T/claims" "$T/verdicts" | sed 's/^/R2 unknown /' || ioerr verdicts

# R3 every PASS has min attempts under each persona (1 for type: ux)
PERSONAS=$(sed -n 's/^personas: *//p' "$R" | tr -d ',')
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
    split("",cnt); claim="" }' "$S" "$R"

# R4 every FAIL/UNVERIFIABLE points at a finding that has repro: or reason:
grep -E '^### C[0-9]+ — (FAIL|UNVERIFIABLE)' "$R" | grep -vE '→ F-[0-9]+-[0-9]+' | sed 's/^/R4 no finding: /'
{ grep -oE '^### C[0-9]+ — (FAIL|UNVERIFIABLE) → F-[0-9]+-[0-9]+' "$R" || [ $? = 1 ]; } | awk '{print $NF}' | sort -u > "$T/need" || ioerr need
awk '/^### F-[0-9]+-[0-9]+ /{f=$2} /^- (repro|reason):/{if(f) ok[f]=1} END{for(k in ok) print k}' "$R" | sort -u > "$T/have" || ioerr have
comm -23 "$T/need" "$T/have" | sed 's/^/R4 no repro: /' || ioerr have

# R5 no repo source path in Files opened outside Entry points. Repo files are
# listed relative to repo_root; scratch payloads and scripts are absolute
# (or under $HOME) and are the verifier's own, so they are not checked.
awk '/^## Entry points/{p=1;next} /^## /{p=0} p' "$S" > "$T/entry" || ioerr entry
awk '/^## Files opened/{p=1;next} /^## /{p=0} p' "$R" \
  | grep -oE '[^ ]+\.(java|kt|ts|tsx|js|py|go|rs|rb|cs|swift|scala|c|cpp|h)$' \
  | grep -vE '^(/|\$HOME|~)' \
  | while read -r f; do grep -qF -- "$f" "$T/entry" || echo "R5 $f"; done

# R6 header verdict after triage (--after-triage only). BLOCKED when there is
# at least one claim section and every one is UNVERIFIABLE; else CLEAN when no
# loop finding, no UNVERIFIABLE claim and no spec-level finding; else FINDINGS.
if [ "$after" = 1 ]; then
  loop=$(awk '/^## Findings/{p=1} /^## Spec-level/{p=0} p && /^- triage: loop/' "$R" | wc -l | tr -d ' ')
  unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R")
  spec=$(awk '/^## Spec-level findings/{p=1;next} /^## /{p=0} p && /^### F-/' "$R" | wc -l | tr -d ' ')
  claims=$(grep -cE '^### C[0-9]+ — (PASS|FAIL|UNVERIFIABLE)' "$R")
  if [ "$claims" -gt 0 ] && [ "$unv" = "$claims" ]; then
    vwant=BLOCKED
  elif [ "$((loop + unv + spec))" = 0 ]; then
    vwant=CLEAN
  else
    vwant=FINDINGS
  fi
  vhave=$(sed -n 's/^verdict: //p' "$R" | head -n 1)
  [ "$vwant" = "$vhave" ] || echo "R6 want $vwant have $vhave"
fi

# R7 coverage line matches the claim sections (re-run after step 6)
pass=$(grep -cE '^### C[0-9]+ — PASS' "$R"); fail=$(grep -cE '^### C[0-9]+ — FAIL' "$R")
unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R")
att=$(awk '/^## Claims/{p=1} /^## Findings/{p=0} p && /^  [0-9]+\. /' "$R" | wc -l | tr -d ' ')
def=$(grep -c '^- triage: deferred' "$R")
want="claims: $((pass+fail+unv))  pass: $pass  fail: $fail  unverifiable: $unv  attempts: $att  deferred: $def"
have=$(awk '/^## Coverage/{getline; print; exit}' "$R")
[ "$(echo "$want" | tr -s ' ')" = "$(echo "$have" | tr -s ' ')" ] || echo "R7 want [$want] have [$have]"
}

# Collect the lines through a pipe, not a temp file, and stop with 2 when
# rules did not finish (ioerr, or a signal such as SIGXFSZ).
out="$(rules)" || exit 2
[ -n "$out" ] || exit 0
printf '%s\n' "$out"
exit 1
