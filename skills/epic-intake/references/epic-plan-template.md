# Epic plan template

Three files share this page: `plan.md` (what the planner writes and the
human may edit before `go`), `graph.json` (what the factory dispatches
from), and the epic record `status.json`. All live in
`$FACTORY_HOME/_epics/<KEY>/`.

## `plan.md`

Exact shape. One `## T<n>:` section per ticket, in dependency order. The
skill fills `created:` after the `ticket` gate; everything else is the
planner's. A human may edit any field before `go`; the skill re-reads and
re-validates the file after the gate.

```markdown
# Plan: KEY — <container title>
goal: <one sentence in the author's words>
non-goals: <sibling container titles and anything the sources exclude>
generated: <iso>   source: epic-planner | splits
repo: owner/repo or unknown

## T1: <summary, imperative, under 80 characters>
work_type: code | research | measure | decision | rollout | closeout
size: S | M | L
repo: owner/repo or unknown
area: <module or path or unknown>
blocks: T3, T4                # tickets that cannot start until this is done; empty when none
created:                      # filled by the skill: KEY-123
reason: <one sentence: why this is its own ticket>
source: <"quoted phrase" from description | comment by <who> <date> | source NN | (inferred)>

<Description: the outcome, the constraint, the pointer to the source. Two
to six sentences. No implementation steps.>

Acceptance criteria:
- <observable behaviour, present tense>
- <negative criterion for every validation or permission statement>

## T2: ...

## Edges
- T1 blocks T3
- T1 blocks T4
- T3 blocks T5

## Soft
- T2 and T4 touch the same area (<area>); run them in sequence if the factory has one slot

## Splits                      # only written by step 4b; same fields per half
### S1: from KEY-45 (<original summary>)
- code: <summary>; size; acceptance criteria
- rollout: KEY-45 keeps the bake; signal that ends it: <metric or date>
created:

## Open questions
- <one line each; the planner's doubts a human may settle before go>
```

Validation the skill runs before the gate and again after `go`:

- Every ticket has `work_type`, `size`, `reason`, `source`, a description
  and at least one acceptance criterion.
- `blocks:` names only tickets in this file; no cycles.
- No `L` without a reason mentioning why it is not split.
- A `closeout` ticket exists when the goal mentions a report, write-up,
  retro or re-check, and it is last.

## `graph.json`

```json
{
  "epic": "KEY-100",
  "generated": "2026-10-21T03:10:00Z",
  "profile": "discovered",
  "nodes": [
    {"key": "KEY-101", "summary": "Add the consolidation flag and config", "work_type": "code",
     "size": "S", "status": "done", "ready": false, "repo": "owner/repo", "blockers": [],
     "readiness": "ready", "gate_on_ready": false},
    {"key": "KEY-102", "summary": "Decide the cut-over date for region B", "work_type": "decision",
     "size": "S", "status": "open", "ready": true, "repo": null, "blockers": [],
     "readiness": "ready", "gate_on_ready": true},
    {"key": "KEY-103", "summary": "Route region B through the new pool", "work_type": "code",
     "size": "M", "status": "open", "ready": false, "repo": "owner/repo",
     "blockers": ["KEY-102"], "readiness": "needs-ac", "gate_on_ready": false},
    {"key": "KEY-104", "summary": "Verify node savings after consolidation", "work_type": "measure",
     "size": "S", "status": "open", "ready": false, "repo": null,
     "blockers": ["KEY-103", "EXT-7"], "readiness": "ready", "gate_on_ready": false},
    {"key": "KEY-105", "summary": "Close out: write up savings and schedule re-check",
     "work_type": "closeout", "size": "S", "status": "open", "ready": false, "repo": null,
     "blockers": ["KEY-101", "KEY-102", "KEY-103", "KEY-104"], "readiness": "ready",
     "gate_on_ready": false}
  ],
  "edges": [
    {"from": "KEY-101", "to": "KEY-103", "type": "blocks"},
    {"from": "KEY-102", "to": "KEY-103", "type": "inferred"},
    {"from": "KEY-103", "to": "KEY-104", "type": "blocks"},
    {"from": "KEY-101", "to": "KEY-105", "type": "blocks"},
    {"from": "KEY-102", "to": "KEY-105", "type": "blocks"},
    {"from": "KEY-103", "to": "KEY-105", "type": "blocks"},
    {"from": "KEY-104", "to": "KEY-105", "type": "blocks"}
  ],
  "soft": [{"a": "KEY-103", "b": "KEY-104"}],
  "cycles": [],
  "external_blockers": {"EXT-7": "in_progress"},
  "ready_set": ["KEY-102"]
}
```

Field rules:

- `status` is the tracker's `status_category`: `open | in_progress | done |
  cancelled`. Done children dropped from the table still appear as nodes
  with `status: done` when another node names them in `blockers[]`.
- `ready` is true only when `status == open`, every key in `blockers[]` is
  `done` or `cancelled` (external keys looked up in `external_blockers`),
  `readiness == ready`, and the key is in no entry of `cycles[]`.
- `edges[]` holds only pairs inside the container. `type: blocks` came
  from a tracker link; `type: inferred` came from text and may also have
  been written back as a link when both ends are children.
- `cycles[]` is a list of key lists. The factory never dispatches a member.
- `gate_on_ready` tells the heartbeat to write a recommendation and DM
  rather than dispatch.
- `ready_set` is derived; the factory recomputes it every tick and
  rewrites `generated`.

## Epic record `status.json`

A run's `status.json` shape (`../../pipeline/references/state-schema.md`)
with only the fields that apply:

```json
{
  "key": "KEY-100",
  "profile": "discovered",
  "mode": "epic",
  "level": 1,
  "stage": "intake",
  "harness": "claude-code",
  "ticket": {"url": "https://…", "summary": "…"},
  "children": ["KEY-101", "KEY-102", "KEY-103", "KEY-104", "KEY-105"],
  "gates": ["ticket"],
  "pending_gate": null,
  "instructions": [],
  "gaps": [],
  "lock": {"owner": null, "since": null},
  "costs": {"spawns": 0, "by_stage": {}, "wall_minutes": 0},
  "history": [{"ts": "…", "event": "created from front door"}]
}
```

`stage` ∈ `intake | gated | planned | dispatching | done | stopped`.
`pending_gate` is `ticket` while gated. `<front door> KEY go` clears it and
re-invokes `epic-intake KEY` with the original flags recorded in
`history[]`. `dispatching` and `done` are written by `factory`.
