---
name: factory
description: The engine's dispatcher. Claims tickets that carry the auto label, or the ready set of an epic graph, and runs each through the front door in its own dispatched session up to a parallel limit, tracking the shift in _factory/shift.json and closing it with a summary. Invoked by the heartbeat for an open shift or by a front door (`factory --label`, `factory --epic KEY`); run by name only to debug a shift.
argument-hint: "[--label <label> [--project X] [--parallel N]] | [--epic KEY [--stack]] | (no args: one pass on the open shift)"
metadata:
  tags: [factory, engine, dispatcher, heartbeat]
---

# Factory

Fills dispatch slots with tickets and keeps the tracker honest about who is
working on what. It never implements anything itself: every ticket runs
through `<front door> KEY`, either in a dispatched session or, when the
profile has no `dispatch`, inline one at a time. State is one file,
`$FACTORY_HOME/_factory/shift.json` (`references/shift-schema.md`).

Read before acting: `references/shift-schema.md`,
`pipeline/references/state-schema.md`, `pipeline/references/capabilities.md`,
`pipeline/references/hygiene.md` (label names), `pipeline/references/gates.md`.

## Entry forms

```
factory --label <label> [--project X] [--parallel N]   open or continue a label shift
factory --epic KEY [--stack] [--parallel N]            open or continue an epic shift
factory                                                one pass on the open shift (heartbeat)
factory --close                                        force the summary and close the shift
```

The front door name comes from `config.front_door` (for example `/intake`
or `/intake-oss`) and is stored in the shift the moment it opens, so later
heartbeat passes reuse it even if the config changes.

## Workflow

Copy this and track it:

```
- [ ] 1. Load config, profile, shift
- [ ] 2. Reconcile running tickets
- [ ] 3. Compute candidates
- [ ] 4. Fill free slots
- [ ] 5. Epic bookkeeping
- [ ] 6. Close the shift when everything is terminal
- [ ] 7. Write shift.json, print the 5-line status
```

### 1. Load config, profile, shift

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json` with
defaults (`config-schema.md`) and `profile.md`. Read the profile's
`## tracker` `notes:` for renamed labels; engine names are `factory-auto`,
`factory-running`, `factory-blocked`, `factory-gated` (`hygiene.md`).
Read `## dispatch`: `tool: none` means inline mode.

Shift file `_factory/shift.json`:

- Exists and `closed` is null: load it. `--label` or `--epic` given with a
  different mode or epic than the open shift → stop and print the open
  shift; one shift at a time. `--parallel N` updates `parallel`.
- Missing or closed, and `--label`/`--epic` given: create it from the
  schema with `started`, `mode`, `label` (default `factory-auto`),
  `project`, `epic`, `stack`, `parallel` (default `config.parallel`),
  `front_door`, `tickets: []`.
- Missing or closed, no arguments: print `no open shift` and stop.

Append `<iso> factory pass` to `_factory/log.md`.

### 2. Reconcile running tickets

For each ticket with `state: running`:

1. `dispatch.status(handle)` when a handle exists. Record `last_status`.
2. Read `$FACTORY_HOME/<KEY>/status.json`. Map `stage` to the shift state
   with the transition table in `shift-schema.md`:
   `done` → `done`; `escalated` → `escalated`; `gated` → `gated`;
   `stopped` → `gated` with `note: stopped by a human`; any other stage →
   still `running`.
3. The dispatch says the session ended but the stage is not terminal →
   `escalated` with `note: session ended at stage <stage>`; the heartbeat
   may resume the run later, so leave the label change in place for a
   human to notice.
4. Apply label hygiene once per transition (record `labelled: <state>` in
   the ticket entry so a re-run does not repeat it):
   - `done`: `tracker.labels(KEY, remove: [factory-running])`, set
     `finished`.
   - `escalated`: `tracker.labels(KEY, add: [factory-blocked], remove:
     [factory-running])`, set `finished`.
   - `gated`: no label change; add `note: gated on <pending_gate>` and the
     resume command `<front door> KEY go`. A gated ticket keeps its slot
     only when `pending_gate` is `merge`; other gates free the slot.
5. A ticket that was `gated` and whose stage left `gated` goes back to
   `running` (same handle, or a new one if the dispatch ended).

`config.offline`: compute every transition, write it to the shift, log the
label calls that would run, make no tracker call.

### 3. Compute candidates

**Label mode.** `tracker.search` for: label `<label>`, not label
`factory-running`, not label `factory-blocked`, status category `open`,
project `<project>` when given, ordered by rank then priority. Drop any key
already in `tickets[]` with a state other than `queued`. Drop keys whose
`$FACTORY_HOME/<KEY>/status.json` has stage `done`, `escalated` or
`stopped` (the label was left behind; log it as `stale label`). Append new
keys as `queued`.

**Epic mode.** Read `_epics/<KEY>/graph.json` (nodes with `key`,
`work_type`, `repo`, `readiness`; edges `blocks`). Missing → invoke
`epic-intake KEY --dry-run` once to produce it, then continue; still
missing → stop and say so. Recompute the ready set from live data, not
from the file: `tracker.get` each child's status; a child is ready when it
is open, `readiness` is `ready`, and every `blocks` predecessor is done or
cancelled (the same rule `epic-intake` uses for its ready set).
With `--stack`, a predecessor in the same repository counts as satisfied
once its run has `branch.pushed_sha` set and its stage is `pr` or later;
that child is marked `stacked_on: <predecessor>`. Exclude children already
`running`, `done`, `gated` or `escalated` in the shift. Children with work
type `decision` or `rollout` are never dispatched here; `epic-intake`
labels them `factory-gated` and the heartbeat DMs when their blockers
clear. `closeout` becomes ready only when every other child is done.

Order: epic mode by graph order (predecessors first, then the planner's
order); label mode by the tracker's ordering.

### 4. Fill free slots

`free = parallel - count(running) - count(gated on merge)`. For the first
`free` queued tickets, in order:

1. **Claim.** `tracker.labels(KEY, add: [factory-running])`. Then one
   `tracker.comment` line after `voice.polish(chat)`: where it runs (the
   dispatch handle or "inline on <hostname>"), the shift's start time, and
   `<front door> KEY stop` as the way to pull it. Record `claimed: <iso>`
   before anything else so a crash between claim and spawn is visible.
2. **Stack seed** (`--stack` and `stacked_on` set). Read the
   predecessor's `status.json`: `repo` and `branch.name`. Write
   `$FACTORY_HOME/<KEY>/status.json` as a seed if it does not exist:
   `key`, `profile`, `harness`, `mode: code`, `epic: <epic>`, `stage:
   prepare`, `round: 1`, `gates` from config, `repo` copied with
   `repo.base` set to the predecessor's `branch.name`, `overrides` copied
   verbatim from the predecessor (a train keeps one branch prefix, comment
   prefix and connect tool end to end; the front door never re-seeds an
   existing file), empty `branch`, `pr`, `nurse`, `review`, `sanity`,
   `sentinel`, `history` with one `seeded by factory --stack on
   <predecessor>` entry. The front door's resume path finds the file and
   keeps `repo.base`. If a `status.json` already exists, only set
   `repo.base` when `branch.pushed_sha` is null.
3. **Dispatch.** `dispatch.spawn(prompt: "<front door> KEY", label: KEY)`
   → `handle`. Set `state: running`, `started`, `handle`. The spawned
   session gets its own working copy per `capabilities.md`; the factory
   never checks anything out.
4. **Inline** (`dispatch: none`). At most one ticket per pass: set
   `state: running`, `handle: inline`, write the shift, then invoke
   `<front door> KEY` with the `Skill` tool (it initialises state when
   missing and runs `pipeline KEY`; when `status.json` already exists,
   `pipeline KEY` directly is equivalent). On return, run step 2 for this
   ticket only, then stop filling slots.

A spawn that fails leaves the ticket `queued` with `note: spawn failed:
<reason>` and removes `factory-running`; the next pass retries once, then
marks it `escalated`.

### 5. Epic bookkeeping

Epic mode only, and only when a ticket changed state this pass or the
ready set changed: invoke `epic-intake KEY --dry-run` to regenerate
`_epics/<KEY>/report.md` and the children files, then update the epic's
owned "Factory plan" comment through `tracker.comment` (find the comment
by its first line, edit in place when the profile supports editing, else
post once per day at most). The comment is the table from `report.md`
plus one line per shift ticket: key, state, started, PR when known.

### 6. Close the shift

Terminal states are `done` and `escalated`. Close when every ticket is
terminal and step 3 found no new candidates (label mode), or every child
in the graph is terminal or gated by design (epic mode). `--close` closes
regardless and lists what was still running.

On close:

1. Write `_factory/shift-<YYYY-MM-DD-HHMM>.md`: shift header (mode, label
   or epic, started, closed, parallel), then tables `## Shipped` (key,
   PR, rounds, minutes from `started` to `finished`), `## Gated` (key,
   gate, resume command), `## Escalated` (key, the one question from
   `escalation.md`, resume form), `## Timing` (median and max minutes,
   slot utilisation as busy-slot-minutes over wall minutes). Numbers in
   tables only.
2. `chat.dm` the file's summary after `voice.polish(chat)`: one line per
   section with counts, the file path, and the escalations' questions.
   `chat: none` → print it.
3. Set `closed: <iso>` and move `shift.json` to
   `_factory/shift-<YYYY-MM-DD-HHMM>.json` next to the summary, so the
   heartbeat sees no open shift.

### 7. Write and report

Write `shift.json` whole (`.tmp` then `mv`) with `last_pass: <iso>`.
Print exactly five lines:

```
shift: <mode> <label or epic>  started <iso>  parallel <n>  pass <iso>
running: <n>  <KEY>(<stage> r<round>) ...
queued: <n>  <KEY> ...            gated: <n>  <KEY>(<gate>) ...
done: <n>  <KEY>#<pr> ...         escalated: <n>  <KEY> ...
next: <"filling k slots" | "waiting on running" | "closing shift" | "no open shift">
```

## Heartbeat contract

`pipeline tick` calls `factory` with no arguments when `shift.json` is
open and `heartbeat.factory` minutes have passed since `last_pass`. The
pass is idempotent: a second run with no external change makes no tracker
call and prints the same five lines.

## Harness notes

Without `Skill`, read `<front door>`'s `SKILL.md` and `epic-intake`'s and
follow them inline. Without `dispatch`, inline mode is the only mode; the
shift still records every ticket. Without `chat`, the shift summary is
printed. MCP tools use the prefix in the profile's `## Harness` section.

## Hard rules

- Never call a vendor tool by name; go through the profile.
- Never implement, check out or edit a repository from this skill.
- Post to a ticket only after claiming it; never comment on tickets the
  shift does not own. `epic-intake` owns the epic comment; the factory
  edits only the "Factory plan" comment it created.
- Only `factory` and `epic-intake` add or remove `factory-*` labels.
- Never exceed `parallel`; `gated on merge` runs count as occupied.
- One shift at a time; never delete a shift file, only move it.
- Never dispatch `decision`, `rollout` or an unready child.
- Never write outside `$FACTORY_HOME`.
