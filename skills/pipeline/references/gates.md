# Gates

A gate is a named pause where a human may look before the factory
continues. Gates are listed in `config.json.gates` (default `["merge"]`),
overridable per run by an instruction (`<front door> KEY gates spec,merge`).

| Gate | Where | What the human sees |
|---|---|---|
| `ticket` | before any tracker `create` (single ticket, epic batch, decomposer split) | the drafted ticket(s) or `plan.md` |
| `spec` | after the spec lint, before the builder | `spec.md` and `spec-critique.md` |
| `pr` | before `pr.create` | the title and body, the diff stat |
| `merge` | before `pr.merge` | PR url, checks, sanity verdict, review state |

System gates are raised by a stage that cannot proceed without an answer
and has no safe default: `repo` (which repository to change), `measure`
(no observability tool), `decision` (decision and rollout modes). They use
the same mechanics below and are always on.

## Behaviour

- Interactive session (a human is typing): `AskUserQuestion` with options
  `go`, `stop`, and `other` for an instruction. Continue on `go`.
- Unattended (a dispatched run, a heartbeat pass, no human): set
  `stage: gated`, `pending_gate: <name>`, append to `history[]`, send
  `chat.dm` with what to review and the exact resume command
  `<front door> KEY go`, and exit cleanly.
- `<front door> KEY go` clears `pending_gate`, restores the stage the gate
  guards, and continues.
- `<front door> KEY stop` sets `stage: stopped`. The heartbeat skips it.
  `go` reopens it.
- An instruction left while gated (`<front door> KEY <text>`) is applied by
  the stage that resumes.

A gate never repeats for the same stage and round unless the artefact it
guards changed.
