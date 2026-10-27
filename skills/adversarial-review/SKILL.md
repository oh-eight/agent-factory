---
name: adversarial-review
description: One black-box verification round for a ticket. Spawns one verifier per persona (fuzzer, attacker, stranger) that attacks every claim in spec.md without seeing source, then merges, lints, triages the reports and writes the round verdict the pipeline reads. Invoked by the pipeline engine after spec-task with a ticket key; run by name only to debug a round (`adversarial-review KEY`).
argument-hint: "<KEY>"
metadata:
  tags: [factory, engine, verification, adversarial]
---

# Adversarial review

The builder says the claims hold. This skill tries to prove it wrong, from
the outside, three different ways at once, and writes down exactly what it
tried. A round ends CLEAN only when every persona ran every claim, nothing
broke, and the report survives a mechanical lint. Everything else sends the
ticket back through `prepare` or trips the valve in `pipeline`.

Read before acting: `references/report-template.md` (shape and lint),
`references/triage.md` (severity, defer rule, ledger),
`agents/verifier.md` (what a persona may and may not do),
`../pipeline/references/{state-schema,config-schema,harness,governor,hygiene}.md`.

## Workflow

Copy this and track it:

```
- [ ] 1. Load state, check the tree, record head and spec hash
- [ ] 2. Spawn one verifier per persona (one message, parallel)
- [ ] 3. Check the tree again; dirty → INVALID
- [ ] 4. Merge persona reports into round-N.md
- [ ] 5. Lint rules 1-5 and 7; re-prompt once; still failing → INVALID
- [ ] 6. Triage; recompute verdict; rule 6 and 7
- [ ] 7. Update ledger.json
- [ ] 8. Hygiene comment, stage, return
```

Variables used below: `FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`,
`D="$FACTORY_HOME/$KEY"`, `S="$D/spec.md"`, `V="$D/verification"`,
`N` = `status.json.round`, `R="$V/round-$N.md"`, `T="$(mktemp -d)"`.

### 1. Load and preflight

1. Load `config.json` with defaults, `profile.md`, `$D/status.json`. Missing
   status → stop: the pipeline did not initialise this run. `stage` must be
   `verify`; otherwise stop and say what it is.
2. `personas` = `config.personas` (default `fuzzer, attacker, stranger`).
   `min_attempts` = 3; claims with `type: ux` use 1.
3. In `repo.path`: `git rev-parse --abbrev-ref HEAD` equals `branch.name`
   and `git status --porcelain` prints nothing. A dirty tree here is the
   pipeline's problem, not the verifier's: stop and report it.
4. Record `head=$(git rev-parse HEAD)`, `base=status.json.repo.base_sha`,
   `spec_hash=$(sha256sum "$S" | cut -d' ' -f1)`, `started=<iso>`.
5. `mkdir -p "$V"`; one `scratch-round-$N-<persona>/` per persona under `$V`
   (outside the repo). Append `<iso> verify round $N start` to `run.log`.
6. Previous reports per persona: `ls "$V"/round-*-<persona>.md` for rounds
   below `N`, or `none`.

### 2. Spawn the personas

One `Agent` call per persona, all in **one message** so they run in
parallel. `subagent_type: general-purpose`, model `inherit`
(`governor.md`), `description: "verifier <persona> for KEY"`, prompt = the
full text of `agents/verifier.md` followed by:

```
## Inputs
- key: KEY
- round: N
- persona: fuzzer | attacker | stranger
- spec: $D/spec.md
- repo_root: <repo.path, expanded>
- branch: <branch.name>
- head_sha: <head>
- base_sha: <base>
- scratch: $V/scratch-round-N-<persona>/
- previous_reports: <comma-separated paths> | none
- min_attempts: 3
- min_attempts_ux: 1
- catalogue: <absolute path of this skill's references/attack-catalogue.md>
- template: <absolute path of this skill's references/report-template.md>
- output: $V/round-N-<persona>.md
- isolation: subagent
```

Never pass: code, diffs, builder output, `context.md`, `build/` paths,
`spec-impl-notes.md`, other personas' reports or scratch dirs, anything
from your own conversation. The verifier's isolation is prompt-level; the
only things that enforce it are this inputs list and the checks in steps 3
and 5.

Append one line per spawn to `costs.json`
(`{"stage":"verify","role":"verifier:<persona>","model":"inherit",...}`)
and bump `status.json.costs.spawns`. Over `budget.max_agent_spawns` → do
not spawn; write `verdict: INVALID` with `lint: budget` and go to step 8.

### 3. Repository integrity

After every persona has returned, in `repo.path`:

```bash
git rev-parse HEAD            # must equal $head
git status --porcelain        # must print nothing
```

Any output → save it to `$V/round-$N-tree.txt`, then
`git checkout -- . && git clean -fd` to restore the tree. A changed HEAD →
`git reset --hard "$head"`. Record `verifier modified repo` in `run.log`
and `history[]`. The round is **INVALID**: still merge (step 4) so the
findings are kept, but write `verdict: INVALID` and
`lint: verifier modified repo` at the top and skip steps 5 and 6.

A persona that returned without writing its `output` file counts as
`verdict: BLOCKED` with every claim UNVERIFIABLE and a single env finding
`reason: persona returned no report`.

### 4. Merge

Write `$R` in the exact shape of `report-template.md`. Header
`personas:` lists every persona in the order spawned; `isolation:` is the
value passed in (all personas carry the same one).

Per claim `C<n>` present in `$S` (skip `status: removed-*`):

- verdict: FAIL if any persona says FAIL; else UNVERIFIABLE if any persona
  says UNVERIFIABLE; else PASS. A claim a persona did not report is
  UNVERIFIABLE with `reason: not reported by <persona>`.
- `baseline:` from the first persona that ran it; the others' baselines go
  under their `attempts (<persona>)` block as attempt 0 only when they
  differ.
- one `- attempts (<persona>):` block per persona, numbered as written.

Findings: collect every `### F-` block from every persona file (both
`## Findings` and `## Spec-level findings`). Group by `fingerprint:`.
One merged block per fingerprint, renumbered `F-N-1`, `F-N-2`, … in order
of first appearance; `personas:` lists who reported it; severity is the
highest reported; `repro:` is the shortest one that reproduces; others go
to `note:`. `repeat-of:` is the id of the same fingerprint in the most
recent earlier merged report (`grep -l "fingerprint: <fp>" "$V"/round-*.md`
with round below `N`), else `none`. Claim verdict lines point at the
merged ids (`### C4 — FAIL → F-N-1`). Spec-level findings (`claim: spec`)
go under `## Spec-level findings` as full `### F-` blocks.

`## Environment` is the union, one `### <persona>` sub-block each.
`## Files opened` is the sorted union, duplicates removed. `## Coverage`
is recomputed in step 6. Header `verdict:` is provisional until step 6:
BLOCKED if every claim is UNVERIFIABLE, FINDINGS if any FAIL,
UNVERIFIABLE or spec-level finding exists, else CLEAN.

### 5. Lint (structural rules)

Run every command; any output is a failure for that rule. Rule 6 runs in
step 6 because it depends on triage.

```bash
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
```

On any failure, find the persona at fault: R3 names it; for R2, R4, R5
grep the per-persona files for the claim, finding or path. Re-prompt that
persona **once**: same inputs plus
`- relint: <rule numbers and the failing lines>` and
`- draft: <its existing report path>`. Re-merge (step 4) and re-lint. If it
still fails, write at the top of `$R`:

```
verdict: INVALID
lint: R3 C2 attacker 1; R5 src/foo.ts
```

keep the rest of the file, skip step 6, continue at step 7. Two INVALID
rounds in a row trip the valve in `pipeline`; this skill only records.

### 6. Triage

Follow `references/triage.md`. For each finding under `## Findings`:

- `severity` strictly below `config.triage.defer_below` (default `medium`,
  so `low` only), `category` is not `security`, and the claim's `type:` in
  `$S` is not `security` → **deferred**. Append the full block to
  `$V/deferred-findings.md` (dated, with the round). Unless
  `config.offline`, create a follow-up through `tracker.create` with the
  template in `triage.md` (summary from the finding, description with the
  repro, `tracker.link(KEY, relates, new)`, label `factory-followup`), then
  write `- triage: deferred → <new key>`. Offline → `- triage: deferred →
  (offline)`.
- Everything else, including every env finding and every block under
  `## Spec-level findings` → `- triage: loop`.

Claim lines keep their verdict; a FAIL whose only finding is deferred is
still written FAIL but no longer counts toward the verdict.

Recompute and write the header verdict:

```bash
loop=$(awk '/^## Findings/{p=1} /^## Spec-level/{p=0} p && /^- triage: loop/' "$R" | wc -l | tr -d ' ')
unv=$(grep -cE '^### C[0-9]+ — UNVERIFIABLE' "$R")
spec=$(awk '/^## Spec-level findings/{p=1;next} /^## /{p=0} p && /^### F-/' "$R" | wc -l | tr -d ' ')
# R6: CLEAN iff all three are zero; BLOCKED iff every claim is UNVERIFIABLE; else FINDINGS
```

Rewrite the `## Coverage` line with the step-5 formula (deferred count
now non-zero when applicable) and run R7 again. Write
`finished: <iso>` in the header. Write the file whole (`.tmp` then `mv`).

### 7. Ledger

`$V/ledger.json` maps fingerprint → `{claim, rounds[], status, ticket}`
(`triage.md` has the schema and an example). For this round:

- every fingerprint in `$R` (including spec-level): append `N` to
  `rounds` (no duplicates); `status` = `deferred` with `ticket` when
  triage deferred it, else `open`; `claim` from the block.
- every fingerprint already in the ledger with `status: open` that is
  absent from `$R` → `status: fixed`. `deferred` entries never change.
- an INVALID round still records its findings as `open`; it never marks
  anything `fixed`, because absence in an invalid round proves nothing.

The pipeline's valve reads this file: `rounds: [N-1, N]` with `status:
open` means the same break survived a fix attempt.

### 8. Hygiene, stage, return

- `status.json`: CLEAN → `stage: pr`. FINDINGS, BLOCKED or INVALID →
  leave `stage: verify`; the pipeline applies the valve and decides
  between `round+1` and escalation. Append to `history[]`
  `{ts, event: "verify round N <verdict> fail=<n> unverifiable=<n> deferred=<n>"}`
  and the matching line to `run.log`, plus the `governor.md` checkpoint
  line.
- Hygiene (`hygiene.md`): on FINDINGS, BLOCKED or INVALID, one
  `tracker.comment` after `voice.polish(text, durable)`:
  `Round N: Y findings (Z deferred to follow-ups KEY-…), back to prepare`,
  with BLOCKED or INVALID named as the reason instead of a count. On CLEAN
  post nothing here; the pipeline's `→ pr` comment carries the counts.
  Skip comments when `config.offline`.
- Release nothing: the pipeline holds the lock.

Return under 30 lines: verdict, `head`, `spec_hash`, per-claim one-line
table (`C1 PASS`, `C4 FAIL F-N-1 high loop`, …), counts from
`## Coverage`, deferred follow-up keys, lint result (`ok` or the failing
rules), whether a re-prompt happened, path of `$R`, and the next stage.

## Harness notes

Without `Agent` (Cursor, Codex): read `agents/verifier.md` and run the
personas **sequentially in this session**, one at a time, writing each
persona's report before starting the next. Pass `- isolation: same-session`
in every `## Inputs` block and carry it into the merged header. Follow the
verifier's forbidden list strictly even though the session has seen the
code; the `git status` and `Files opened` checks still apply. Without
`Skill`, `voice.polish` means applying `pipeline/references/prose.md`
inline. Without a tracker, `tracker.create` is the file tracker and still
produces a key.

## Hard rules

- Verifiers get the inputs in step 2 and nothing else. No diffs, no
  source, no builder notes, no transcript.
- Never skip the lint, never hand-edit a persona report to make it pass.
  Fix the merge, re-prompt the persona once, or record INVALID.
- Never mark a round CLEAN with an UNVERIFIABLE claim, a `loop` finding, or
  a spec-level finding, whatever the personas' own verdict lines say.
- `security` findings and claims of `type: security` are never deferred.
- A dirty tree after the personas return is restored and the round is
  INVALID; the state dir is the only place this skill writes.
- Scratch dirs live under `$V`, never inside the repository.
- Follow-up tickets and comments go through capabilities
  (`tracker.create`, `tracker.link`, `tracker.comment`); never a vendor tool
  by name. Offline runs write the files and skip the tracker.
