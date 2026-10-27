---
name: spec-task
description: Build phase of the engine behind /intake and /intake-oss. Turns a ticket's context into a verifier-safe spec, has that spec independently checked and critiqued, then builds, tests, security-reviews, UX-checks, mutation-audits and burn-in tests the change on a pushed branch, ready for adversarial review. Invoked by `/intake` or `/intake-oss` through `prepare` with a ticket key; run by name only to debug one round (`spec-task KEY`).
argument-hint: "<KEY>"
metadata:
  tags: [factory, engine, spec, build, qa, security]
---

# Spec task

One round of spec, build and break-it-yourself for ticket KEY. The input is
the state directory `prepare` left behind (`intake.md`, `sources/`,
`context.md`, cartography). The output is a pushed branch, `spec.md` with
every claim `built`, and `build/round-N/*`, which the verifiers and the PR
body read later. The skill names no vendor tool; it asks the profile for
capabilities (`../pipeline/references/capabilities.md`).

Read before acting: `../pipeline/references/spec-format.md` (the spec shape
and its lint), `governor.md` (models, budgets, `costs.json`), `gates.md`,
`harness.md`, `state-schema.md`.

## Setup

```bash
FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"
RUN="$FACTORY_HOME/<KEY>"            # must exist with status.json, intake.md, context.md
N=$(jq .round "$RUN/status.json")    # round
B="$RUN/build/round-$N"; mkdir -p "$B/shots" "$B/mutants" "$RUN/history"
```

- `SKILL_DIR` is the directory holding this file. Role files are
  `$SKILL_DIR/agents/<role>.md`; the spec format is
  `$SKILL_DIR/../pipeline/references/spec-format.md`.
- Load `config.json` with defaults (`config-schema.md`), `profile.md`, and
  cartography `$FACTORY_HOME/_repos/<owner>-<repo>.md` from
  `status.repo.remote`. Missing cartography → stop and say `prepare` has
  not run.
- Set `stage: spec`, append `<iso> spec start round=N` to `run.log`.
- Read `status.instructions[]`. Apply what this stage can honour (skip a
  role, an answer to an open decision for the spec-writer, extra gates) and
  append `applied: <text>` to `history[]`.
- Resume rule: every step below names its output file. Skip a step whose
  output exists and is complete; `$B/summary.md` with `outcome: complete`
  means the round is done, return at once.
- `REPO` is `status.repo.path` (expand `$HOME`), `BRANCH` is
  `status.branch.name`, `BASE` is `status.repo.base`. If `REPO` is missing,
  recreate it per `state-schema.md` before anything else.

## Spawning a role

```
Agent(
  subagent_type: "general-purpose",
  model: <table below, overridden by config.models[role]>,
  description: "<role> for <KEY> round <N>",
  prompt: <full text of $SKILL_DIR/agents/<role>.md>
          + "\n\n## Inputs\n" + one `- name: /absolute/path or value` line per input
)
```

| Role | `model` |
|---|---|
| spec-writer, intent-verifier, spec-critic | inherit |
| builder, qa, security, mutation-auditor | opus |
| ux | sonnet |

Before each call: if `status.costs.spawns + 1 > budget.max_agent_spawns`,
stop with the valve return (below). After each call: append
`{"stage":"spec","role":"<role>","model":"<model>","started":"<iso>","ended":"<iso>"}`
to `$RUN/costs.json`, bump `status.costs.spawns` and `by_stage.spec`.
Subagents inherit nothing; every path is absolute, with `$HOME` expanded.
A role that returns without writing its output file is re-spawned once
with the line "Your output file is missing; write it first", then counted
as a failed pass.

## Workflow

Copy this and track it:

```
- [ ] 1. spec-writer (full, delta or re-spec)
- [ ] 2. intent-verifier ∥ spec-critic → intent-gaps.md, revision pass(es)
- [ ] 3. Spec lint, snapshot to history/
- [ ] 4. Gate `spec` when enabled
- [ ] 5. builder, confirm pushed
- [ ] 6. qa ∥ security ∥ ux
- [ ] 7. mutation-auditor, qa kill pass
- [ ] 8. Flake burn-in
- [ ] 9. Route blocking findings to builder (inner cap), rest to deferred.md
- [ ] 10. Mark claims built, summary.md, stage verify, return
```

### 1. spec-writer (foreground)

Inputs: `key`, `round`, `mode`, `intake` (`$RUN/intake.md`), `context`
(`$RUN/context.md`), `sources` (`$RUN/sources/`), `cartography`, `status`
(`$RUN/status.json`), `format` (spec-format.md), `spec` (`$RUN/spec.md`),
`impl_notes` (`$RUN/spec-impl-notes.md`), `instructions` (the applicable
instruction text, or `none`), and in delta mode `previous_verification`
(`$RUN/verification/round-$((N-1)).md`), `previous_gaps`
(`$RUN/build/round-$((N-1))/intent-gaps.md`), `previous_critique`
(`.../spec-critique.md`), `previous_builder` (`.../builder.md`).

- Round 1: `mode: full`. Writes `spec.md` and `spec-impl-notes.md`.
- Round N > 1: `mode: delta`. The writer edits `spec.md` in place from the
  previous verification report and the `## Round N delta` section of
  `context.md`, records a Changelog line, keeps claim ids stable.
- `mode: respec` only when `context.md`'s delta says the approach is wrong
  or more than half the claims failed last round
  (`grep -c '— FAIL' round-$((N-1)).md` against the claim count). Ids
  stay stable where the behaviour is the same.

Output: `$RUN/spec.md`, `$RUN/spec-impl-notes.md`.

### 2. intent-verifier ∥ spec-critic (one message, two Agent calls)

Intent-verifier inputs: `key`, `round`, `intake`, `context`, `sources`,
`output` (`$B/intent-checks.md`). It never receives `spec.md` or
`spec-impl-notes.md`; do not mention their paths in its prompt.

Spec-critic inputs: `key`, `round`, `spec`, `cartography`, `format`,
`output` (`$B/spec-critique.md`).

When both files exist, the skill diffs intent checks against claims:

```bash
grep -oE '^### IC-[0-9]+' "$B/intent-checks.md" | sed 's/### //' | sort -u > /tmp/ic.txt
grep -oE 'IC-[0-9]+' "$RUN/spec.md" | sort -u > /tmp/ic-cited.txt
comm -23 /tmp/ic.txt /tmp/ic-cited.txt      # ICs the spec does not cite yet
```

For every uncited IC, read the check and judge: an existing claim covers
it (record `covered by C<n>`), a `## Non-goals` line covers it, or it is a
GAP. Write `$B/intent-gaps.md`:

```markdown
# Intent gaps: KEY — round N
checks: 9  cited: 2  covered: 5  gaps: 2
| IC | check (first line) | verdict | claim |
|---|---|---|---|
| IC-3 | rejects a non-integer argument | GAP | |
| IC-4 | prints usage with no arguments | covered | C2 |
```

Blocking items: any GAP row, any `### SC-n` under `## Blocking` in the
critique. If there are none, continue to step 3.

Otherwise spawn the spec-writer with `mode: revise` and the extra inputs
`intent_checks`, `intent_gaps`, `critique`. It cites every IC on the
covering claim's `source:` line (or in Non-goals), resolves each Blocking
SC and records the Changelog. Then re-run the `comm` above and check every
Blocking SC id appears in `## Changelog`. Anything still open → one more
revise pass. After two passes, continue; the critique travels with the
spec to the gate and the builder, and open items are listed in
`summary.md` under `## Open`.

Output: `$B/intent-checks.md`, `$B/intent-gaps.md`, `$B/spec-critique.md`.

### 3. Spec lint and snapshot

Run exactly these from `spec-format.md`:

```bash
S="$RUN/spec.md"
[ "$(grep -c '^### C[0-9]*:' "$S")" -ge 1 ] || echo "NO CLAIMS"
awk '/^### C[0-9]*:|^## Changelog/{ if (c && !(v&&e&&t)) print "INCOMPLETE " c; c=$0; v=e=t=0 } /^- verify:/{v=1} /^- expect:/{e=1} /^- type:/{t=1} END{ if (c && c !~ /^## Changelog/ && !(v&&e&&t)) print "INCOMPLETE " c }' "$S"
grep -o '^### C[0-9]*' "$S" | sort | uniq -d                       # duplicate ids
grep -q '^## How to run' "$S" || echo "NO HOW TO RUN"
grep '^- verify:' "$S" | grep -oE '[^ ]+\.(java|kt|ts|tsx|js|py|go|rs|rb|cs|swift|scala)\b' | sort -u > /tmp/verify-paths.txt
awk '/^## Entry points/{f=1;next} /^## /{f=0} f' "$S" > /tmp/entry.txt
while read -r p; do grep -qF "$p" /tmp/entry.txt || echo "SOURCE IN VERIFY $p"; done < /tmp/verify-paths.txt
```

The `awk` line checks each claim when the next header or `## Changelog`
arrives, and the last one at end of file (spec-format.md shows a shorter
form that reports every claim; this is the working equivalent). Any
output → spawn the spec-writer (`mode: revise`,
`lint` input holding the output) once; still failing → fix the mechanical
part yourself (never invent a claim) and record it in the Changelog.
Then `cp "$S" "$RUN/history/spec-round-$N.md"`.

Output: `$RUN/history/spec-round-N.md`.

### 4. Gate `spec`

When `spec` is in `config.gates` (or in `status.gates`): follow
`gates.md`. The human sees `$RUN/spec.md` and `$B/spec-critique.md`.
Interactive → `AskUserQuestion` (`go`, `stop`, `other`). Unattended →
`stage: gated`, `pending_gate: spec`, `chat.dm` with both paths and the
resume command, release the lock, exit. The gate does not repeat for the
same round unless `spec.md` changed since (compare with the snapshot).

### 5. builder (foreground)

Inputs: `key`, `round`, `mode: build`, `spec`, `impl_notes`, `context`,
`cartography`, `critique`, `repo`, `branch`, `base`, `previous_report`
(`$RUN/build/round-$((N-1))/builder.md` or `none`), `output`
(`$B/builder.md`).

Afterwards, in `REPO`:

```bash
git fetch origin "$BRANCH" 2>/dev/null
git log "origin/$BRANCH..HEAD" --oneline     # must print nothing
```

Output present but pushes missing → `git push -u origin "$BRANCH"`
yourself, once; still failing → record a `push` gap and continue only when
`status.repo.remote` is empty (a local-only toy), otherwise the valve
return. Record `status.branch.pushed_sha`.

Read `## Decisions needed` and `## Not done`. A non-empty
`## Decisions needed` is the valve condition the pipeline watches for:
write `summary.md` with `outcome: blocked`, leave `stage: spec`, return
with `valve: decision needed — <one line>`. `## Not done` without a
decision → counts as blocking findings for step 9.

`## Spec problems` from the builder go to the spec-writer (`mode: revise`,
input `builder_report`) before step 6 when they make a claim unbuildable
as written; cosmetic ones wait for the next round's delta.

Output: `$B/builder.md`.

### 6. qa ∥ security ∥ ux (one message)

First write the diff the reviewers share:
`git -C "$REPO" diff "$BASE...HEAD" > "$B/diff.patch"` and
`git -C "$REPO" diff --name-only "$BASE...HEAD" > "$B/changed-files.txt"`.

- qa inputs: `key`, `round`, `mode: test`, `spec`, `context`,
  `cartography`, `repo`, `branch`, `base`, `builder_report`,
  `previous_report` (or `none`), `output` (`$B/qa.md`).
- security inputs: `key`, `round`, `spec`, `context`, `cartography`,
  `diff` (`$B/diff.patch`), `repo`, `base`, `output` (`$B/security.md`).
- ux inputs: `key`, `round`, `spec`, `sources`, `context`, `profile`,
  `repo`, `changed_files`, `shots` (`$B/shots/`), `output` (`$B/ux.md`).
  Spawn ux only when `grep -q '^- type: ux' spec.md` or
  `changed-files.txt` matches cartography's frontend patterns (fallback:
  `\.(tsx|jsx|vue|svelte|css|scss|html)$`). Otherwise write `$B/ux.md`
  with one line: `skipped: no ux claims and no frontend files`.

After qa returns, confirm its tests are pushed the same way as step 5.

Output: `$B/qa.md`, `$B/security.md`, `$B/ux.md`.

### 7. mutation-auditor

Skip when `config.mutation` is `false` (write `$B/mutation.md` with
`skipped: config.mutation=false`). Otherwise record
`git -C "$REPO" status --porcelain > /tmp/before.txt`, then spawn with
inputs `key`, `round`, `spec`, `cartography`, `repo`, `base`, `qa_report`,
`scratch` (`$B/mutants/`), `max_mutants: 10`, `output` (`$B/mutation.md`).
The auditor uses the language-specific mutation tool named by cartography
or the profile when there is one, else up to 10 hand mutants on changed
functions in a scratch copy under `scratch`, running QA's tests per mutant
and restoring after each.

Afterwards `git -C "$REPO" status --porcelain | diff - /tmp/before.txt`
must be empty; if not, `git -C "$REPO" checkout -- .` and
`git -C "$REPO" clean -fd -- <paths that appeared>`, and note
`auditor left the tree dirty` in `summary.md` `## Open`. Survivors appear
in `mutation.md` as QA findings. If any: spawn qa with
`mode: kill-survivors`, `findings: $B/mutation.md`, `output: $B/qa-kill.md`.
Survivors qa reports as real bugs (the mutant is behaviour the spec wants
and the code gets wrong) become blocking findings for step 9.

Output: `$B/mutation.md`, optionally `$B/qa-kill.md`.

### 8. Flake burn-in

Take the test ids from `## Tests added or changed` in `qa.md` (and
`qa-kill.md`). For each, run cartography's single-test command
`config.burn_in_runs` times (default 5), or cartography's flake-check
command once when it names one. Write `$B/burn-in.md`:

```markdown
# Burn-in: KEY — round N
runs per test: 5   tests: 7   stable: 7   flaky: 0
| test | runs | passes | verdict |
## Findings
### F-N-flake-1  fingerprint: c3-flaky-timeout  blocking: yes
- claim: C3  category: test-gap  severity: medium
- repro: <command> ×5  observed: 3/5 pass  expected: 5/5
```

Any flaky test → spawn qa with `mode: fix-flaky`, `findings: $B/burn-in.md`,
`output: $B/qa-flaky.md`, then re-run the burn-in for the tests it touched
and append a second table. If qa reports the cause is non-deterministic
production code, the finding is routed to the builder in step 9.

Output: `$B/burn-in.md`.

### 9. Route findings

Collect every finding block from `qa.md`, `qa-kill.md`, `security.md`,
`ux.md`, `mutation.md` (survivors not killed), `burn-in.md`, plus
builder `## Not done` rows. Blocking means `blocking: yes` (see "Findings
in build reports"). Non-blocking → append to `$B/deferred.md`:

```markdown
# Deferred: KEY — round N
| finding | from | severity | why deferred | suggested follow-up |
```

Blocking, pass k = 1 … `budget.max_inner_passes`:

1. Write `$B/fix-pass-k.md`: the blocking finding blocks verbatim.
2. Spawn builder `mode: fix`, `findings: $B/fix-pass-k.md`,
   `output: $B/builder-fix-k.md`. Confirm the push as in step 5.
3. Spawn qa `mode: retest`, `findings: $B/fix-pass-k.md`,
   `builder_report: $B/builder-fix-k.md`, `output: $B/qa-retest-k.md`.
   Only qa re-runs after a fix; security and ux findings are closed when
   qa's retest reproduces the fix with a test or the manual repro from
   the finding.
4. Findings still open after the retest carry to pass k+1.

Cap reached with blocking findings open → `summary.md` with
`outcome: blocked`, `## Open` listing them, `stage: spec` unchanged, return
with `valve: inner passes exhausted — <fingerprints>`.

Output: `$B/deferred.md`, `$B/fix-pass-k.md`, `$B/builder-fix-k.md`,
`$B/qa-retest-k.md`.

### 10. Close the round

1. For each claim the builder (and fix passes) report done, change its
   `- status: open` to `- status: built` in `spec.md`. Claims that were
   `pass-r(N-1)` and unchanged keep that status.
2. Apply `## How to run changes` from the builder reports to `spec.md`
   (the skill edits the spec; roles never do). Add a Changelog line
   `rN: built; How to run: <what changed>`.
3. Write `$B/summary.md`:

```markdown
# Summary: KEY — round N
outcome: complete
branch: <name>  head: <sha>  base: <base>@<sha>
## What was built
<three to eight lines, present tense, no file list>
## Claims
| claim | status | commits | tests |
## How to run changes
## Passes
spec-writer: 2  builder: 1+1  qa: 1+1  inner: 1/3  spawns: 9
## Deferred
<one line per row of deferred.md>
## Open
<critique items carried, gaps recorded, nothing when clean>
```

4. `stage: verify`, `run.log` line `<iso> spec done round=N claims=<n>
   built=<n> inner=<k>/<max>`, update `status.costs`.
5. Return under 30 lines: key, round, claim counts (total, built, by
   type), intent gaps closed, critique items carried, test count and
   suite result, mutation score, burn-in verdict, security verdict,
   inner passes used, head sha, the path of `$B`, and `valve: …` when
   blocked.

## Findings in build reports

Every role that reports a problem uses the verification finding shape
(`../adversarial-review/references/report-template.md`) with a role token
in the id so it cannot collide with the verifiers' `F-N-n`:

```markdown
### F-N-<role>-<n>  fingerprint: <claim-id>-<three-to-five-word-slug>  blocking: yes | no
- claim: C4 | spec
- category: implementation-bug | spec-gap | env | test-gap
- severity: high | medium | low
- repro: <exact steps or command a developer can rerun>
- observed: <what happened>
- expected: <what the spec says>
```

Role tokens: `qa`, `sec`, `ux`, `mut`, `flake`. `blocking: yes` for
`high` and `medium`; `low` is `no`, except security findings, which are
always `yes`. `test-gap` is for weak, missing or flaky tests and routes
to qa; the other categories route to the builder.

## Harness notes

See `../pipeline/references/harness.md`. Without `Agent`, run the roles
inline in the order above, acting as that role with only its inputs in
mind; write each role's output file before starting the next. The
intent-verifier still must not read `spec.md`: run it before opening the
spec in that session or in a fresh session. Record the same `costs.json`
line per inline role with `"model": "same-session"`. Without
`AskUserQuestion`, the gate is a plain question in the reply, then stop.

## Hard rules

- Never call a vendor tool by name; go through the profile.
- Never write outside `$FACTORY_HOME/<KEY>/` and the repository checkout.
  Scratch copies live under `$B/mutants/`, never inside the repository.
- Only the spec-writer and this skill (steps 3 and 10) edit `spec.md`.
  The builder, qa, security, ux and the auditor report spec problems; they
  do not fix them.
- The intent-verifier never sees the spec. The security role never
  executes code or sends requests. QA never changes production code.
- Every branch state the verifiers will see is on `origin/<branch>`.
- Never skip the lint, the gate, the inner-pass cap or the spawn budget.
- Tracker comments and transitions belong to `pipeline`; this skill
  writes none.
