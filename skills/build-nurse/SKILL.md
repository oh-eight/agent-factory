---
name: build-nurse
description: One pass over a pull request's CI. Reads the checks, retries flakes, diagnoses real failures, and hands a real failure back to the pipeline as a finding. Invoked by the heartbeat (`pipeline tick`) for every run in stage `nurse`, or by a front door given a PR or CI build URL; run by name only to debug one PR (`build-nurse <PR number | PR url | KEY>`).
argument-hint: "<PR number | PR url | KEY>"
metadata:
  tags: [factory, shipping, ci, nurse]
---

# Build nurse

A pass looks at one PR's checks once and leaves. Green: done. Pending: come
back later. Red: decide whether to retry, blame the change, or blame the
world, write that down, and exit. The heartbeat calls it every
`config.heartbeat.nurse` minutes; nothing in here waits or polls.

Everything comes through the profile (`pipeline/references/capabilities.md`):
`pr.view`, `pr.checks`, `pr.files`, `ci.failed_jobs`, `ci.root_cause`,
`ci.logs`, `ci.retry`, `chat.dm`. Read the profile's `## pr` and `## ci`
sections before the first call. Read `references/flake-patterns.md` before
classifying anything.

## Workflow

```
- [ ] 1. Resolve the run
- [ ] 2. Early exits
- [ ] 3. Read the PR and its checks
- [ ] 4. Green or pending
- [ ] 5. Failures: collect, classify
- [ ] 6. Flake → retry
- [ ] 7. Real → diagnose and attribute
- [ ] 8. Close the pass
```

### 1. Resolve the run

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`.

| Input | Resolution |
|---|---|
| `KEY` (`[A-Z][A-Z0-9]+-\d+` or `LOCAL-\d+`) | `$FACTORY_HOME/<KEY>/status.json` → `pr.number`, `repo.remote` |
| PR number or PR url (`…/<owner>/<repo>/pull/<n>`, `…/merge_requests/<n>`) | grep `$FACTORY_HOME/*/pr.md` for the number or url → the directory name is KEY |
| CI build url | `ci.status` or the build's PR link → PR → KEY as above |

No `status.json` for the PR → stop with one line: `BUILD-NURSE: no run owns
<pr>; start one through the front door`. The nurse never creates state.

Load `config.json`, the profile stamped in `status.json.profile`, and the
cartography file `$FACTORY_HOME/_repos/<owner>-<repo>.md` when it exists
(it knows how to run CI targets locally).

### 2. Early exits

Each prints exactly one line and stops, in this order:

1. Profile `## ci` says `tool: none` → append `ci: none` to
   `status.json.gaps[]` (once), set `nurse.done = true`, log
   `no CI capability; nurse done`, print `BUILD-NURSE: no CI (<KEY>)`. The
   next pass hits rule 3 and says nothing new.
2. `status.json.stage` is not `nurse` → `BUILD-NURSE: <KEY> is in stage
   <stage>; nothing to do` (pass `--force` to run anyway when debugging).
3. `nurse.done` → `BUILD-NURSE: <KEY> already green at <last_head>`.

### 3. Read the PR and its checks

`pr.view(n)` → state, `head_sha`, base branch, url. Merged or closed →
`nurse.done = true`, log it, print one line, stop.

If `head_sha != nurse.last_head`: a new push. Set
`nurse.last_head = head_sha`, `nurse.retries = {}`, `nurse.blocked = null`,
`nurse.done = false`. Log `new head <sha7>`.

`pr.checks(n)` → `[{name, state, url, job}]`. Partition by `state`.

### 4. Green or pending

- Every check `success` (and at least one check exists) → `nurse.done =
  true`, log `GREEN`, print `BUILD-NURSE: GREEN <pr url>`, then one
  `chat.dm` in the `chat` register: PR url, head, checks count. Stop.
- Some `pending`, none `failure` → log `pending <n> checks`, print
  `BUILD-NURSE: <KEY> waiting on <n> checks`. Stop. No DM.
- Any `failure` → step 5.

### 5. Failures: collect and classify

For each failing check, `ci.failed_jobs(pr)` filtered to that check gives
the jobs (name, id, url, exit status, duration). For each job, take the
first evidence you can get cheaply: the structured `ci.root_cause` when the
profile has one, else the last 200 lines of `ci.logs(job)`.

Classify the job against, in this order:

1. The **Never retry** list in `references/flake-patterns.md`. A hit here
   is `real` regardless of anything else.
2. The profile's `ci.flake_patterns` file when the line is not `none`
   (vendor patterns; read it, do not copy it).
3. `## Learned` and then the generic table in `references/flake-patterns.md`.

The first match wins. No match → `real`. Record per job:
`{job, classification: flake|infra|real, pattern, evidence (≤ 5 lines)}`.

### 6. Flake → retry

For every job classified `flake` with `nurse.retries[job] < 2` (job keyed
by its stable name, not its run id): `ci.retry(job)`, then
`nurse.retries[job] += 1`. Log one line per retried job:
`retry <job> (<n>/2) pattern=<name>`. Print `BUILD-NURSE: retried <n> job(s)
on <KEY>` and **stop the pass**; the next tick reads the new result. Do not
diagnose other jobs in the same pass while a retry is in flight.

A `flake` job at 2 retries is treated as `real` from here on; note
`retries exhausted` in its evidence.

### 7. Real and infra → diagnose and attribute

For each remaining job, write `nurse/failure-<N>.md` (N = next free number;
skip if a file already names this job at this head):

```markdown
# Failure N — <job name>
head: <sha>  check: <check name>  url: <job url>  pass: <nurse.passes>
classification: real | infra   pattern: <name or none>   retries: <n>/2
## Evidence
<root_cause output or the log tail, trimmed to what matters>
## Hypothesis
<one paragraph: what broke and why you think so>
## Local repro
<the cartography command for this target, or "unknown">
```

Then decide attribution with `pr.files(n)` (the changed paths) in hand:

| Attribution | Evidence | Action |
|---|---|---|
| **this change** | the failing test, target or module is among the changed files or imports one; the error message names a symbol, file or string the diff added or removed; a lint or compile error in a changed file | A below |
| **base broken** | the failing target is untouched by the diff, and the same failure shows on the base branch's latest build (`ci.status` for the base when the profile exposes it, else the profile's `notes`) | B |
| **infra** | classification `infra`, or an `infra`-shaped error with no test or compile failure at all | B |
| **unclear** | none of the above fits | B, say so |

**A. Real failure from this change.** Write (or append a round section to)
`nurse/ci-findings.md` in the verification finding shape
(`adversarial-review/references/report-template.md`):

```markdown
# CI findings round <round> — <KEY>
verdict: FINDINGS
head: <sha>  source: build-nurse  pass: <n>
## Findings
### F-<round>-ci-1  fingerprint: ci-<job-slug>-<failure-slug>  repeat-of: <F id | none>  personas: build-nurse
- claim: <C<n> whose verify covers this target, else `ci`>
- category: implementation-bug | env
- severity: high | medium
- triage: loop
- repro: <local command from cartography, else the CI job url and "no local repro known">
- observed: <the assertion, compile error or lint line, verbatim>
- expected: <the job passes; or what the test asserts>
- note: <one line linking to nurse/failure-N.md>
```

`category: env` only when the fix is in build or test configuration the
diff touched; otherwise `implementation-bug`. `severity: high` for compile
and test failures, `medium` for lint and format. Set `repeat-of` by reading
earlier `ci-findings.md` sections with the same fingerprint (the valve in
`pipeline` counts repeats). Then `stage = prepare`, `round += 1`, append
`{ts, event: "ci-findings → prepare round N"}` to `history[]`, log it,
print `BUILD-NURSE: REAL FAILURE → pipeline <KEY>`. No DM; the pipeline
comments on the ticket when it picks the round up.

**B. Base broken, infra, or unclear.** Stage stays `nurse`. Set
`nurse.blocked = {reason: base|infra|unclear, head, job, since}`. If
`nurse.blocked` was already set for this head and job, print
`BUILD-NURSE: <KEY> still blocked (<reason>)` and stop with no DM. Otherwise
`chat.dm` once, `chat` register: PR url, job name, the one-line hypothesis,
the path of `failure-N.md`, and what would unblock it (a base fix, a retry
by hand, or an answer). Log `blocked <reason> <job>`. Print
`BUILD-NURSE: BLOCKED (<reason>) <pr url>`.

### 8. Close the pass

Every pass, whichever branch it took after step 2: `nurse.passes += 1` and
one line appended to `nurse/log.md`:

```
<iso> pass=<n> head=<sha7> <outcome: green | pending k | retry job | findings F-… | blocked reason | no-ci | merged>
```

Write `status.json` whole (temp file, then rename). Release nothing else;
the nurse takes no lock, it only edits the `nurse`, `stage`, `round`,
`gaps` and `history` fields.

## Idempotency

The same PR, same head, same check states → the second pass is one printed
line plus one log line. Guarantees: retries are keyed by head (step 3
reset); `failure-N.md` is not rewritten for a known job and head;
`ci-findings.md` is appended once per head (check the `head:` line of the
last section first); the blocked DM fires once per head and job; the GREEN
DM fires once because `nurse.done` flips once per head.

## Harness notes

The nurse is a single role (`governor.md`: sonnet) and spawns nothing, so it
runs the same in every harness. Without a `Skill` tool, the heartbeat reads
this file and follows it inline. Without MCP tools, every `ci.*` operation
maps to the `cli:` form in the profile; when the profile has no `ci` at
all, step 2 rule 1 applies.

## Hard rules

- Never retry a job that matched the **Never retry** list, and never retry
  the same job more than twice per head.
- Never read source files to diagnose; the diff list from `pr.files` and
  the job evidence are enough for attribution. Fixing is the builder's job.
- Never DM except on a change: first green for this head, first block for
  this head and job.
- Never call a vendor tool by name; the profile's `## ci` lines decide.
- Never write outside `$FACTORY_HOME/<KEY>/`.
- One pass, one exit line, one log line.
