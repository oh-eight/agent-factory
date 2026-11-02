# R1 verdict line
[ "$(grep -cE '^verdict: (CLEAN|FINDINGS|BLOCKED)$' "$R")" = 1 ] || echo "R1 verdict"

# R2 every live spec claim has a verdict
awk '/^### C[0-9]+:/{c=$2; sub(/:$/,"",c); ids[c]=1} /^- status: removed-/{rm[c]=1}
     END{for(i in ids) if(!rm[i]) print i}' "$S" | sort > "$T/claims"
grep -oE '^### C[0-9]+ — (PASS|FAIL|UNVERIFIABLE)' "$R" | awk '{print $2}' | sort > "$T/verdicts"
comm -23 "$T/claims" "$T/verdicts" | sed 's/^/R2 missing /'
comm -13 "$T/claims" "$T/verdicts" | sed 's/^/R2 unknown /'

# R3 every PASS has min attempts under each persona (1 for type: ux)
PERSONAS=$(sed -n 's/^personas: *//p' "$R" | tr -d ',')
awk -v min=3 -v personas="$PERSONAS" '
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
grep -oE '^### C[0-9]+ — (FAIL|UNVERIFIABLE) → F-[0-9]+-[0-9]+' "$R" | awk '{print $NF}' | sort -u > "$T/need"
awk '/^### F-[0-9]+-[0-9]+ /{f=$2} /^- (repro|reason):/{if(f) ok[f]=1} END{for(k in ok) print k}' "$R" | sort -u > "$T/have"
comm -23 "$T/need" "$T/have" | sed 's/^/R4 no repro: /'

# R5 no repo source path in Files opened outside Entry points. Repo files are
# listed relative to repo_root; scratch payloads and scripts are absolute
# (or under $HOME) and are the verifier's own, so they are not checked.
awk '/^## Entry points/{p=1;next} /^## /{p=0} p' "$S" > "$T/entry"
awk '/^## Files opened/{p=1;next} /^## /{p=0} p' "$R" \
  | grep -oE '[^ ]+\.(java|kt|ts|tsx|js|py|go|rs|rb|cs|swift|scala|c|cpp|h)$' \
  | grep -vE '^(/|\$HOME|~)' \
  | while read -r f; do grep -qF -- "$f" "$T/entry" || echo "R5 $f"; done

# R7 coverage line matches the claim sections (re-run after step 6)
pass=$(grep -cE '^### C[0-9]+ — PASS' "$R"); fail=$(grep -cE '^### C[0-9]+ — FAIL' "$R")
unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R")
att=$(awk '/^## Claims/{p=1} /^## Findings/{p=0} p && /^  [0-9]+\. /' "$R" | wc -l | tr -d ' ')
def=$(grep -c '^- triage: deferred' "$R")
want="claims: $((pass+fail+unv))  pass: $pass  fail: $fail  unverifiable: $unv  attempts: $att  deferred: $def"
have=$(awk '/^## Coverage/{getline; print; exit}' "$R")
[ "$(echo "$want" | tr -s ' ')" = "$(echo "$have" | tr -s ' ')" ] || echo "R7 want [$want] have [$have]"
