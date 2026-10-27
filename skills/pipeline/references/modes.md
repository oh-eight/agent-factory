# Modes

`status.json.mode` decides which stage machine a run follows. The front door
sets it from a label (`factory-mode:<mode>`), from the epic graph, from the
brief, or defaults to `code`.

## `code`

The full machine in `pipeline/SKILL.md`: prepare → spec-task → verify
(loop) → pr → nurse → merge → sentinel → learn → done.

## `research`

For tickets that ask a question or want a proposal, investigation or
write-up.

1. `prepare` gathers context exactly as for code (cartographer when a
   repository is named, sources, `code.search`, `knowledge.search`, `obs`
   and `incidents` when the wording calls for them). No branch is created.
2. Spawn `pipeline/agents/researcher.md` → `research.md`: the question as
   understood, findings with one evidence link each, options with
   trade-offs when the ticket asks for a decision, a recommendation, and
   open questions. When the ticket asks for a document, structure the body
   as the profile's document template if it names one, else as
   Problem / Findings / Options / Recommendation / Next steps.
3. Spawn `spec-task/agents/intent-verifier.md` with the ticket and
   `research.md` (not a spec): does the deliverable answer what was asked?
   Gaps → one researcher pass.
4. `voice.polish(durable)`; `tracker.comment` with the full text; when the
   profile has a document store and the ticket asks for a page, create it
   and link it. `tracker.transition(done)`. Stage `learn`.

## `measure`

For tickets that ask for a baseline, a verification of savings, or a
number.

1. Context as above.
2. Spawn `pipeline/agents/measurer.md`: names each metric the ticket
   implies, writes the query for it through `obs`, picks the window the
   ticket states (else the last 7 days and, when a change date is known,
   the same span before it), runs the queries, writes `measurement.md`
   with one table per metric, the queries used, explore links, caveats,
   and a one-paragraph reading.
3. Comment it on the ticket; `done`; `learn`. A re-run appends a dated
   section instead of overwriting.
4. No `obs` capability → `measurement.md` holds the metric list and the
   queries that would run; comment that; stage `gated` with
   `pending_gate: measure` and a DM saying observability is missing.

## `decision` and `rollout`

Not executed by the factory. Spawn the researcher with the ticket, its
epic context and sibling tickets to write `recommendation.md` (the decision
or rollout plan the evidence supports, the risks, the reversal path). Stage
`gated`, `pending_gate: decision`, DM. `go` marks the ticket `done` with
the recommendation as the closing comment; an instruction with a different
decision is recorded first.

Rollout tickets that are really a configuration change plus a bake period
are split by `epic-intake` into a `code` child (the change) and a
`rollout` child (the bake), so the code part still gets the full loop.

## `closeout`

A `research` run that executes last in an epic: it reads every sibling's
`research.md`, `measurement.md`, `pr.md` and sentinel log, and writes the
epic's closing comment (what shipped, what was measured, what is deferred).
