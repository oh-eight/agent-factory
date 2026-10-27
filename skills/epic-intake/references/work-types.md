# Work types

Every work item the factory touches has one of six types. The type decides
which stage machine `pipeline` follows (`../../pipeline/references/modes.md`)
and which labels `epic-intake` adds (`../../pipeline/references/hygiene.md`).
A `factory-mode:<mode>` label already on the ticket overrides any reading
below.

## Recognition

Read the summary's verb first; it is usually right. Then the acceptance
criteria; then the description. When they disagree, the acceptance criteria
win: a ticket whose criteria describe shipped behaviour is `code` even if
the summary says "investigate".

| Type | Verbs | Nouns and shapes | The deliverable is |
|---|---|---|---|
| `code` | implement, add, fix, migrate, remove, refactor, upgrade, wire, expose, support | endpoint, flag, field, job, handler, test, schema, dependency bump, bug | a change in a repository with tests, behind a flag when risky |
| `research` | investigate, evaluate, explore, compare, assess, propose, spike, design, understand why | options, trade-offs, root cause, feasibility, approach, one-pager, RFC | a written answer with evidence and a recommendation |
| `measure` | measure, baseline, quantify, verify savings, confirm the drop, record, count | latency, cost, error rate, p99, usage, before/after, dashboard panel | a dated table of numbers with the queries that produced it |
| `decision` | decide, approve, choose, sign off, agree, confirm go/no-go, pick | option A or B, vendor, cut-off date, ownership, deprecation | a human's yes or a chosen option, recorded on the ticket |
| `rollout` | roll out, enable in stages, ramp, bake, cut over, flip, migrate traffic, turn on for | percentage, cohort, region, flag value, soak period, canary | a staged exposure watched over time |
| `closeout` | close out, document, write up, summarise, schedule re-check, retro, announce completion, archive | final report, lessons, runbook update, follow-up date, cleanup list | the container's closing comment or page, written last |

Tie-breaks:

- "Investigate and fix": `code` when the fix is in scope and criteria
  describe the fixed behaviour; `research` when the ticket ends at a
  finding, with a follow-up `code` ticket proposed in the readiness
  comment.
- "Measure and improve": two tickets. The `measure` baseline blocks the
  `code` change; a second `measure` after it verifies. Propose the split
  in the readiness comment; do not create tickets.
- A `decision` buried in a `code` ticket ("TBD which library") makes the
  ticket `needs-decision`, not type `decision`. Only a ticket whose whole
  point is the choice is `decision`.
- "Remove the flag after bake" is `code` (the removal) blocked by the
  `rollout` (the bake).
- A ticket with no verb and a noun phrase ("Dashboard for export errors")
  is `code` when the noun is an artefact in a repository, `measure` when
  it is a number, `research` when it is a question.

## Routes

| Type | `pipeline` mode | Labels added by `epic-intake` | Who finishes it |
|---|---|---|---|
| `code` | `code` | `factory-auto` | the factory, through to merge and sentinel |
| `research` | `research` | `factory-auto`, `factory-mode:research` | the factory posts the evidence comment |
| `measure` | `measure` | `factory-auto`, `factory-mode:measure` | the factory posts the dated table; without `obs` it gates |
| `decision` | `decision` | `factory-gated`, `factory-mode:decision` | a human; the factory writes a recommendation when blockers clear and DMs it (`gate_on_ready: true`) |
| `rollout` | `rollout` | `factory-gated`, `factory-mode:rollout` | a human; same recommendation path |
| `closeout` | `research` executed last | `factory-auto`, `factory-mode:closeout` | the factory, after every sibling is done or cancelled |

`decision` and `rollout` nodes carry `gate_on_ready: true` in `graph.json`.
The heartbeat's factory pass watches them: when every blocker is done it
runs the recommendation step from `modes.md` and sends the DM, then waits
for `go`.

## The split rule for `rollout`

Many rollout tickets are two things: a change that has to be built and
reviewed (a configuration value, a flag default, a routing rule, a
deployment manifest) and a period of watching it. The first half is `code`
and deserves the full loop; the second half is `rollout` and deserves a
human.

Split when the text describes both:

- a concrete edit in a repository ("set the flag default to", "bump the
  replica count", "add the region to the allow-list", "change the config
  to"), and
- a staged exposure or wait ("then ramp to", "bake for", "watch for 48 h",
  "enable for 10 % first", "cut over once").

Do not split when the rollout is purely operational (a console toggle, a
runbook step, a percentage change in a feature-flag UI with no repository
edit) or when the change is already a sibling ticket; then the rollout
ticket is blocked by that sibling.

The enricher writes `split: proposed` and both halves under `## Proposed
split`. The skill collects every proposal into `plan.md` under `## Splits`,
runs the `ticket` gate once for the batch, and only then creates the
`code` sibling (`parent` = the container), links `code blocks <original>`,
and treats the original ticket as the `rollout` half. Its readiness comment
names the new key. Nothing is created without the gate, and nothing when
offline.

## Size

| Size | Rule of thumb |
|---|---|
| S | one module, one behaviour, under a day, no flag needed |
| M | a few modules or one service boundary, a flag, a day or two |
| L | several services or teams, data migration, or unknowns the sources do not settle; the decomposer may split it at run time |

Anything the planner would call XL is two or more tickets.
