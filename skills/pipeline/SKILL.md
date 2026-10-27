---
name: pipeline
description: Engine behind /intake and /intake-oss. Drives one ticket from state through prepare, spec, adversarial verification, PR, nurses, merge, deploy watch and learning, plus the shared heartbeat and dashboard. Invoked by a front door with a ticket key; run by name only to debug or resume a run (`pipeline KEY`, `pipeline tick`, `pipeline dashboard`).
argument-hint: "<KEY> | tick | dashboard"
metadata:
  tags: [factory, orchestrator, autonomous]
---

# Pipeline

The per-ticket engine. Everything it needs is in `$FACTORY_HOME/<KEY>/`
(`references/state-schema.md`) and the active profile
(`references/profile-schema.md`). It never names a vendor tool; it asks for
capabilities (`references/capabilities.md`).

Read before acting: `references/state-schema.md`, `references/capabilities.md`,
`references/gates.md`, `references/governor.md`. Read `references/modes.md`
when the mode is not `code`.

## Entry forms

```
pipeline KEY          run or resume the ticket KEY from its stage
pipeline tick         one heartbeat pass (references/heartbeat.md)
pipeline dashboard    render and print the dashboard (references/dashboard.md)
```

## Start of every run

1. `FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json`
   with defaults (`references/config-schema.md`) and `profile.md`.
2. Load `<KEY>/status.json`. Missing → the front door did not initialise
   this run; stop and say so.
3. Take the lock (`state-schema.md`). Younger than 2 hours and owned by
   someone else → stop and print the owner, unless `--force`.
4. Read `instructions[]`; apply any that this stage can honour (repo path,
   gates, skip a role, an answer to an escalation) and append
   `applied: …` to `history[]`.
5. Mode not `code` → follow `references/modes.md` and stop here.
6. Append `<iso> <stage> resume` to `run.log`.

## Stage machine (mode `code`)

```
prepare ─► spec ─► verify ─┬─ CLEAN ─► pr ─► nurse ─► merge ─► sentinel ─► learn ─► done
    ▲                        └─ FINDINGS / BLOCKED / INVALID ─► valve ─┬─ ok ─► round+1 ─► prepare
    │                                                                  └─ tripped ─► escalated
    └── ci-findings / review-findings / sanity "fix code"
```

### `prepare`

Invoke `prepare KEY` (the skill). It writes `context.md`, records repo
and branch, runs the cartographer and decomposer, then invokes `spec-task`
itself. On return expect `stage: verify`. If `train.json` appeared, run
each child as its own `pipeline <child>` in order, each with `repo.base`
set to the previous child's branch; this run waits and reports.

### `verify`

Rebase prelude in the repo: `git fetch origin && git rebase origin/<base>`.
Conflicts → spawn the builder (`spec-task/agents/builder.md`) with the
conflict list as a fix pass (counts toward `max_inner_passes`); run the
quick test command from cartography once; record `repo.base_sha`.

Invoke `adversarial-review KEY`. Read the merged verdict from
`verification/round-<round>.md`.

- CLEAN → `stage: pr`.
- FINDINGS, BLOCKED or INVALID → valve check below. Not tripped →
  `round += 1`, `stage: prepare`, hygiene comment, continue.

### Valve

Trip when any holds:

- `round >= budget.max_rounds`.
- The same fingerprint appears in two consecutive rounds after a fix
  attempt (`ledger.json` shows `rounds: [N-1, N]` with `status: open`).
- BLOCKED in two consecutive rounds (the environment cannot be fixed by
  re-spec).
- INVALID in two consecutive rounds.
- The builder's report says a claim needs a decision the spec does not
  make.
- Any budget in `governor.md` exceeded.

Tripped → write `escalation.md` (why, the open findings with repro, what
each round tried, the one question that unblocks), `stage: escalated`,
hygiene comment, `chat.dm` with the question and the resume command,
release the lock, stop. Resume path: `<front door> KEY <answer>` then
`<front door> KEY go`; the answer lands in `instructions[]` and round N+1
of `prepare` reads it.

### `pr`

Gate `pr` (`references/gates.md`). Check `git log origin/<branch>..HEAD`
is empty; push if not. Produce title and body through the profile's
`pr.body` (a vendor skill or `references/pr-template.md`) with these
pointers: `intake.md` → Problem; latest `build/round-N/summary.md` →
Solution; `qa.md`, `mutation.md`, `burn-in.md` and the merged report's
`## Coverage` → Testing; the ticket key → Context; `train.json` → Stack.
State in the request that the front door is the user's instruction to
open a PR. `pr.create` as draft unless `config.pr_ready`; `pr.connect` with
`status.json.overrides.connect` when set, else the profile's `connect:`,
skipping `none`. Write `pr.md`. `tracker.transition(in_review)`,
hygiene comment. `stage: nurse`. Make sure the heartbeat is running
(`references/heartbeat.md`).

### `nurse`

Owned by the heartbeat: `build-nurse` and `review-nurse` passes on their
intervals, `pr-sanity-check` once. Findings they write
(`nurse/ci-findings.md`, `nurse/review-findings.md`, a sanity "fix code")
set `stage: prepare` and `round += 1`; the valve applies. A sanity "fix
description" sets `stage: pr` with an instruction; the `pr` stage then
runs its body step in update mode (`pr.edit`, since `pr.number` is set),
clears `sanity.verdict` so the heartbeat re-checks, and returns to
`nurse`.

When `nurse.done`, `sanity.verdict == MATCH`, `review.open_items == 0` and
`pr.view` shows the approvals the repository requires → `stage: merge`.

### `merge`

Gate `merge` (default on). `pr.merge(n, squash)` with auto-merge when the
host supports it. Record `pr.merged_sha`, `tracker.transition(done)`,
hygiene comment. `stage: sentinel` when the profile has `obs` or `deploy`,
else `stage: learn` with a gap recorded.

### `sentinel`

Owned by the heartbeat: `deploy-sentinel` passes until the window closes.
HEALTHY → `stage: learn`. Anomaly → `stage: incident`, DM with the evidence
and the prepared revert command, stop; a human decides.

### `learn`

Invoke `learner KEY`. Then `stage: done`, final report (below), release
the lock. Under a dispatcher, also update `_factory/shift.json`.

## Hygiene and accounting

After every stage change: one tracker comment per `references/hygiene.md`,
one `run.log` line, and a `governor.md` checkpoint after every round.

## Final report (printed, under one screen)

Key, mode, rounds, claims and attempts from the last merged report,
findings deferred to follow-ups, PR url and merge sha, sentinel verdict,
lessons written, last checkpoint, and the path of the state directory.

## `pipeline tick` and `pipeline dashboard`

Follow `references/heartbeat.md` and `references/dashboard.md` exactly.
Both are idempotent and safe to run at any time.

## Harness notes

See `references/harness.md`. Without `Skill`, read the named skill's
`SKILL.md` and follow it inline. Without `Agent`, roles run in this
session; mark verifier reports `isolation: same-session`.

## Hard rules

- Never call a vendor tool by name; go through the profile.
- Never write outside `$FACTORY_HOME` and the repository being changed.
- Never skip the valve, the gates in `config.gates`, or the lint on a
  verification report.
- A missing required capability stops the run with a message naming it.
- Prose that reaches people goes through `voice.polish` first.
