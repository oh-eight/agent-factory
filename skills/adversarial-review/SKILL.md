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
tried. A round ends CLEAN when every persona ran every claim, nothing
broke, and the report survives a mechanical lint. It ends SHIP when every
claim ran and what broke is only known issues: nothing high, nothing
`security`, nothing `medium` on a `type: security` claim. Both go to `pr`.
Everything else sends the ticket back through `prepare` or trips the valve
in `pipeline`.

Read before acting: `references/report-template.md` (shape and lint),
`references/triage.md` (severity, blocking and defer rules, ledger),
`agents/verifier.md` (what a persona may and may not do),
`../pipeline/references/{state-schema,config-schema,harness,governor,hygiene}.md`.

## Workflow

Copy this and track it:

```
- [ ] 1. Load state, check the tree, record head and spec hash
- [ ] 2. Spawn one verifier per persona (one message, parallel)
- [ ] 3. Check the tree again; dirty → INVALID
- [ ] 4. Merge persona reports into round-N.md
- [ ] 5. Lint (script, rules 1-5 and 7); re-prompt once; still failing → INVALID
- [ ] 6. Triage; lint --after-triage; write the want values
- [ ] 7. Update ledger.json
- [ ] 8. Hygiene comment, stage, return
```

Variables used below: `FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`,
`D="$FACTORY_HOME/$KEY"`, `S="$D/spec.md"`, `V="$D/verification"`,
`N` = `status.json.round`, `R="$V/round-$N.md"`, `SKILL_DIR` = the
directory holding this SKILL.md.

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
UNVERIFIABLE or spec-level finding exists, else CLEAN. Never `SHIP` here;
only step 6 writes it.

### 5. Lint (structural rules)

The lint is a script in this skill; rule 6 runs in step 6 because it
depends on triage. Run it on the merged report, with `min_attempts` from
step 1 (`type: ux` claims always need 1):

```
"$SKILL_DIR/scripts/lint-report.sh" --min-attempts <min_attempts> "$S" "$R"
```

It prints one `R<n> …` line per failure. Exit 0: pass. Exit 1: lint
failure. Any other exit: stop the round and report stderr; never a pass,
never INVALID.

An R1 or R7 line is a merge error of this skill, never of a persona: step 4
writes the header verdict and the Coverage line. For R1, rewrite the header
verdict line as step 4 says (exactly one `verdict:` line). For R7, write the
`want` line of `R7 want [<line>] have [<line>]` as the line after
`## Coverage`, adding that heading when it is missing. Then run the script
again. If an R1 or R7 line is still printed after that rerun, record INVALID
as below. This never re-prompts a persona.

On an R2–R5 failure, find the persona at fault: R3 names it; for R2, R4, R5
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

Follow `references/triage.md`. For each finding under `## Findings` and
`## Spec-level findings`, in this order:

- **Blocking** first: severity `high` (spec-level included), category
  `security` (any severity), or `medium` or worse on a claim whose `type:`
  in `$S` is `security`. An unrecognised severity or category, or a
  `- claim:` that is not `spec` and names no claim in `$S`, also blocks.
  → `- triage: loop`. A blocking finding is never deferred.
- Not blocking, under `## Findings`, severity strictly below
  `config.triage.defer_below` (default `medium`, so `low` only), and the
  claim's `type:` is not `security` → **deferred**. Append the full block
  to `$V/deferred-findings.md` (dated, with the round). Unless
  `config.offline`, create a follow-up through `tracker.create` with the
  template in `triage.md` (summary from the finding, description with the
  repro, `tracker.link(KEY, relates, new)`, label `factory-followup`), then
  write `- triage: deferred → <new key>`. Offline → `- triage: deferred →
  (offline)`.
- Every other finding, spec-level `low` and `medium` included → **known
  issue**, `- triage: known → <key>`. `<key>` is the run's one combined
  follow-up issue (`triage.md`, "Known-issue follow-up template"): the
  first round with a known issue creates it through `tracker.create` and
  `tracker.link`; a later round adds its `## Round N` section with
  `tracker.comment`, finding the key from a ledger entry with
  `status: known`. Offline → `- triage: known → (offline)`.

Claim lines keep their verdict; a FAIL whose only finding is deferred or
known is still written FAIL but does not block.

Then lint the triaged report with all seven rules, reading the exit status
as in step 5:

```
"$SKILL_DIR/scripts/lint-report.sh" --after-triage --min-attempts <min_attempts> "$S" "$R"
```

The script's `want` values are what the skill writes:

- `R6 triage <id> want <w> have <h>` → set that finding's triage to `<w>`:
  `loop`, or `known → <key>` with the combined follow-up as above (add the
  finding to this round's section). A deferred ticket already created for
  it stays open; a finding that stops being a known issue comes out of the
  round's section.
- `R6 want <V> have <W>` → write `verdict: <V>` in the header (`CLEAN`,
  `SHIP`, `FINDINGS` or `BLOCKED`).
- `R7 want [<line>] have [<line>]` → write the `want` line after
  `## Coverage` (the deferred count is now non-zero when applicable).

These lines are the skill's own triage or merge error, and the skill
never re-prompts a persona for them. Run the script once more. A line it
still prints → write `verdict: INVALID` and step 5's `lint:` header line at
the top of `$R`, keep the rest, and continue at step 7. Write
`finished: <iso>` in the header. Write the file whole (`.tmp` then `mv`).

### 7. Ledger

`$V/ledger.json` maps fingerprint → `{claim, rounds[], status, ticket}`
(`triage.md` has the schema and an example). For this round:

- every fingerprint in `$R` (including spec-level): append `N` to
  `rounds` (no duplicates); `status` = `deferred` or `known` with `ticket`
  when triage deferred it or made it a known issue, else `open`; `claim`
  from the block.
- every fingerprint already in the ledger with `status: open` that is
  absent from `$R` → `status: fixed`. `deferred` and `known` entries never
  change.
- an INVALID round still records its findings as `open`; it never marks
  anything `fixed`, because absence in an invalid round proves nothing.

The pipeline's valve reads this file: `rounds: [N-1, N]` with `status:
open` means the same break survived a fix attempt.

### 8. Hygiene, stage, return

- `status.json`: CLEAN or SHIP → `stage: pr`. FINDINGS, BLOCKED or
  INVALID → leave `stage: verify`; the pipeline applies the valve and
  decides between `round+1` and escalation. Append to `history[]`
  `{ts, event: "verify round N <verdict> fail=<n> unverifiable=<n> deferred=<n> known=<n>"}`
  and the matching line to `run.log`, plus the `governor.md` checkpoint
  line.
- Hygiene (`hygiene.md`): on FINDINGS, BLOCKED or INVALID, one
  `tracker.comment` after `voice.polish(text, durable)`:
  `Round N: Y findings (Z deferred to follow-ups KEY-…), back to prepare`,
  with BLOCKED or INVALID named as the reason instead of a count. On CLEAN
  or SHIP post nothing here; the pipeline's `→ pr` comment carries the
  counts and the known-issue follow-up key.
  Skip comments when `config.offline`.
- Release nothing: the pipeline holds the lock.

Return under 30 lines: verdict, `head`, `spec_hash`, per-claim one-line
table (`C1 PASS`, `C4 FAIL F-N-1 high loop`, `C2 FAIL F-N-2 medium
known`, …), counts from `## Coverage`, deferred follow-up keys, the
known-issue follow-up key and count, lint result (`ok` or the failing
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
- Never mark a round CLEAN or SHIP with an UNVERIFIABLE claim or a
  blocking finding (`high`; category `security`; `medium` or worse on a
  `type: security` claim; anything unrecognised), and never CLEAN with a
  known issue, whatever the personas' own verdict lines say. Personas
  never write SHIP.
- A `deferred` line never hides a blocking finding.
- `security` findings and findings on claims of `type: security` are never
  deferred. A `security` finding is never a known issue; a `low` finding of
  another category on a `type: security` claim is one.
- A dirty tree after the personas return is restored and the round is
  INVALID; the state dir is the only place this skill writes.
- Scratch dirs live under `$V`, never inside the repository.
- Follow-up tickets and comments go through capabilities
  (`tracker.create`, `tracker.link`, `tracker.comment`); never a vendor tool
  by name. Offline runs write the files and skip the tracker.
