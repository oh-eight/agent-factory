# Shift file

`$FACTORY_HOME/_factory/shift.json` is the dispatcher's only state. One
shift is open at a time. Closed shifts are moved to
`_factory/shift-<YYYY-MM-DD-HHMM>.json` next to their summary
`shift-<YYYY-MM-DD-HHMM>.md`. `_factory/log.md` is append-only, one line per
pass.

## Schema

```json
{
  "started": "2026-10-21T08:00:00Z",
  "closed": null,
  "last_pass": "2026-10-21T09:30:00Z",
  "mode": "epic",
  "label": "factory-auto",
  "project": null,
  "epic": "ABC-100",
  "stack": true,
  "parallel": 2,
  "front_door": "/intake-oss",
  "tickets": [
    {
      "key": "ABC-101",
      "state": "done",
      "handle": "sess-7f3a",
      "claimed": "2026-10-21T08:00:10Z",
      "started": "2026-10-21T08:00:20Z",
      "finished": "2026-10-21T09:05:00Z",
      "labelled": "done",
      "stacked_on": null,
      "pr": "https://…/pull/41",
      "last_status": "ended",
      "note": null
    },
    {
      "key": "ABC-102",
      "state": "running",
      "handle": "sess-91c0",
      "claimed": "2026-10-21T08:30:00Z",
      "started": "2026-10-21T08:30:05Z",
      "finished": null,
      "labelled": "running",
      "stacked_on": "ABC-101",
      "pr": null,
      "last_status": "running",
      "note": null
    },
    {
      "key": "ABC-103",
      "state": "gated",
      "handle": "sess-2b77",
      "claimed": "2026-10-21T08:30:00Z",
      "started": "2026-10-21T08:30:08Z",
      "finished": null,
      "labelled": "running",
      "stacked_on": null,
      "pr": "https://…/pull/42",
      "last_status": "ended",
      "note": "gated on merge; resume: /intake-oss ABC-103 go"
    },
    {
      "key": "ABC-104",
      "state": "queued",
      "handle": null,
      "claimed": null,
      "started": null,
      "finished": null,
      "labelled": null,
      "stacked_on": null,
      "pr": null,
      "last_status": null,
      "note": null
    }
  ]
}
```

## Fields

| Field | Meaning |
|---|---|
| `started`, `closed`, `last_pass` | ISO times; `closed` null while open |
| `mode` | `label` or `epic` |
| `label` | label searched in label mode (engine name; the profile may rename it) |
| `project` | optional project filter in label mode |
| `epic`, `stack` | epic key and whether `blocks` chains in one repo run as a PR train |
| `parallel` | slots; `config.parallel` at creation, `--parallel` overrides |
| `front_door` | the command used for every dispatch and resume hint, fixed at creation |
| `tickets[].state` | `queued`, `running`, `done`, `gated`, `escalated` |
| `tickets[].handle` | `dispatch.spawn` handle, `inline`, or null |
| `tickets[].claimed` | when `factory-running` was added; set before the spawn |
| `tickets[].labelled` | last state whose label change was applied, so a re-run does not repeat it |
| `tickets[].stacked_on` | predecessor key when `repo.base` was seeded from its branch |
| `tickets[].pr` | copied from `<KEY>/status.json.pr.url` when known |
| `tickets[].last_status` | last `dispatch.status` result |
| `tickets[].note` | free text: gate, failure reason, stale label |

## State transitions

| From | To | When | Tracker effect |
|---|---|---|---|
| (candidate) | `queued` | found by `tracker.search` or in the epic ready set | none |
| `queued` | `running` | a slot is free; claim then spawn (or inline) | add `factory-running`; one comment |
| `queued` | `queued` + note | spawn failed, first time | remove `factory-running` |
| `queued` | `escalated` | spawn failed twice | add `factory-blocked` |
| `running` | `running` | stage is any of `prepare`, `spec`, `verify`, `pr`, `nurse`, `merge`, `sentinel`, `incident`, `learn` | none |
| `running` | `gated` | stage `gated` (keeps its slot only when `pending_gate` is `merge`), or stage `stopped` | none; note records the gate and resume command |
| `gated` | `running` | stage left `gated` | none |
| `running` | `done` | stage `done` | remove `factory-running` |
| `running` | `escalated` | stage `escalated`, or dispatch ended with a non-terminal stage | add `factory-blocked`, remove `factory-running` |
| any | (removed) | key no longer carries the label and never ran | none |

Terminal states: `done`, `escalated`. `gated` is not terminal; a shift with
only `gated` tickets stays open until a human resumes or `--close`.

## Summary file (`shift-<date>.md`)

```markdown
# Shift <mode> <label or epic>
started: <iso>   closed: <iso>   parallel: <n>   front door: <name>

## Shipped
| Key | PR | Rounds | Minutes |

## Gated
| Key | Gate | Resume |

## Escalated
| Key | Question | Resume |

## Timing
| Median minutes | Max minutes | Slot utilisation |
```

Rounds come from `<KEY>/status.json.round`; the question from the last
paragraph of `<KEY>/escalation.md`; slot utilisation is busy-slot-minutes
divided by `parallel × wall minutes`.
