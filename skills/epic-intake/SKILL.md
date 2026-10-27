---
name: epic-intake
description: Turn a container of work items (epic, milestone, project, goal) into a dependency graph the factory can dispatch. Plans tickets when the container is empty, enriches existing children with one owned comment each when it is not, routes every child by work type, and reports on the container. Invoked by a front door (/intake or /intake-oss) when a tracker key is a container (tracker.hierarchy_level ≥ 1); run by name only to debug (`epic-intake KEY --dry-run`).
argument-hint: "<KEY> [--run] [--stack] [--rewrite] [--dry-run] [--include-done]"
metadata:
  tags: [factory, epics, planning, tracker, orchestrator]
---

# Epic intake

A container is a tracker item whose children are the work. This skill reads
the container, makes sure every child is something `pipeline` can run (a
work type, a size, acceptance criteria, known blockers), writes the graph
the `factory` dispatches from, and leaves one comment on each ticket so a
human can see the same picture. It creates tickets only when the container
has none, and only behind the `ticket` gate.

Everything vendor-specific lives in the profile. Read the profile's tracker
`notes:` for how children attach to a container and which link types mean
"blocks" before touching `tracker.children` or `tracker.link`.

Read before acting: `../pipeline/references/{capabilities,state-schema,
gates,governor,hygiene,harness}.md`, `references/work-types.md`,
`references/epic-plan-template.md`, and `../ticket-refiner/SKILL.md` for
step 4b.

## Entry forms

```
epic-intake KEY                  plan or enrich, report, stop
epic-intake KEY --run            then invoke `factory --epic KEY`
epic-intake KEY --run --stack    factory runs each `blocks` chain in one repo as a PR train
epic-intake KEY --rewrite        allow description rewrites on children (default: comment only)
epic-intake KEY --dry-run        files only; no tracker, chat or label writes; print the table
epic-intake KEY --include-done   keep done children in the graph (default: skip them)
```

`config.offline` behaves like `--dry-run` for writes. Both are called
"offline" below.

## Workflow

Copy this and track it:

```
- [ ] 1. Resolve the key and its level
- [ ] 2. Container context → context.md
- [ ] 3. Children → children list
- [ ] 4a. No children → plan, gate, create     |  4b. Children → enrich, refine when a human is present, comment
- [ ] 5. Graph → graph.json
- [ ] 6. Route → labels
- [ ] 7. Report → report.md, container comment, DM, optional factory
```

State for this container: `E="$FACTORY_HOME/_epics/<KEY>/"` with
`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Files are written whole
(`.tmp` then `mv`). The epic record is `E/status.json`, shaped like a run's
`status.json` where the fields apply (`epic-plan-template.md`); take and
release its lock the same way a run does.

### 1. Resolve

`tracker.get(KEY)` and `tracker.hierarchy_level(KEY)`.

- Level 0: say "KEY is a work item, not a container" and hand it back to
  the front door, which runs `pipeline`. Stop.
- Level 1: continue.
- Level 2: `tracker.children(KEY)` gives level-1 containers. Run this skill
  for each (its own `_epics/<child>/`, same flags), then write the goal
  summary `E/report.md`: one row per container (key, title, children,
  ready, blocked, gated, done) with a link to each container's report,
  and post it as the goal's "Factory plan" comment (step 7 mechanics).
  Stop after the summary; `--run` passes to each container's run.

Record `key`, `level`, `profile` and `harness` in `E/status.json`,
`stage: intake`.

### 2. Context

Write `E/context.md`:

- Title, description, status, labels, assignee, dates.
- Comments, newest last, trimmed to decisions and constraints.
- Every link in the description and comments fetched per
  `../pipeline/references/sources.md` into `E/sources/NN-<slug>.md`.
  Tracker keys in the text are sources too.
- Parent container (level 2) summary in one paragraph, when there is one.
- Sibling container titles under the same parent: these are the
  boundaries. A child that belongs to a sibling's scope is flagged in step
  4b, not moved.
- `## Not fetched` for links over the sources budget.

Re-runs refresh only what changed; `sources/` is never fetched twice.

### 3. Children

`tracker.children(KEY)` returns direct children with `status_category`,
`links[]`, `labels[]`. Keep `open` and `in_progress`; drop `cancelled`;
drop `done` unless `--include-done` (done children still count as
satisfied blockers in step 5, so fetch their keys and status even when
dropped from the table). Write the list to `E/children.json`.

For each kept child, `tracker.get` the full ticket (description, comments,
links) into `E/children/<child>.extract.md` using the sources file shape.
Nothing is written to the tracker in this step.

### 4a. No children: plan

Spawn `agents/epic-planner.md` (model `inherit`) with `context`,
`sources`, `cartography` (`$FACTORY_HOME/_repos/<owner>-<repo>.md` when
the container names a repository and the file exists, else `none`),
`work_types`, `template`, `output: E/plan.md`. It writes ordered tickets:
summary, description, acceptance criteria as observable behaviours, work
type, size S/M/L, `blocks` edges, and a one-line reason each is its own
ticket. Validate: every ticket has all fields; no ticket larger than M
without a reason; edges reference tickets in the plan; a closeout ticket
exists when the container asks for reporting.

**Gate `ticket`** (`gates.md`), once for the whole batch:

- Interactive: show `E/plan.md` path and the table; `AskUserQuestion` with
  `go`, `stop`, `other`. The human may edit `plan.md` before `go`; re-read
  it after `go` and re-validate.
- Unattended: `E/status.json` `stage: gated`, `pending_gate: ticket`,
  `history[]` entry, `chat.dm` with the plan path, the table and
  `<front door> KEY go`. Exit. On `go` the front door re-invokes this
  skill, which finds `pending_gate: ticket` and continues here.

After the gate, unless offline: for each plan ticket not yet carrying a
`created:` key, `tracker.create` with `parent: KEY`, the work type's
labels from step 6, then write `created: <NEWKEY>` back into `plan.md`.
Then `tracker.link(a, blocks, b)` for every edge whose ends both exist.
Record the new keys in `E/children.json` and continue to step 5. Offline:
graph nodes use `PLAN-<n>` placeholders and `report.md` says so.

### 4b. Children exist: enrich

Spawn `agents/child-enricher.md` (model `sonnet`) once per child, five at
a time: five `Agent` calls in one message, wait, next five. Inputs:
`extract` (the child's extract), `context` (`E/context.md`),
`profile`, `work_types`, `siblings` (`E/children.json`), `output:
E/children/<child>.md`. Each writes: work type (per
`references/work-types.md`), size, readiness (`ready | needs-ac |
needs-decision | blocked`), acceptance criteria drafted when missing,
dependency edges inferred from text ("after X", "once Y is live") that are
not yet tracker links, likely repository and area, open questions, and a
`## Pipeline readiness` section holding the comment text verbatim.

**Refine with the human present.** When a human is typing (`AskUserQuestion`
available, not offline, no `intake-context` trailer) and `config.refine.mode`
is not `off`, children the enrichers marked `needs-ac` or `needs-decision`
go through `ticket-refiner <child> --epic KEY --rounds <left>` before any
comment is posted. Order: children with no open blocker first (they would
be in the ready set), then by size ascending. `left` starts at
`config.refine.epic_rounds` (default 6) for the whole container and goes
down by the `rounds_used` each call returns; stop calling when it reaches
zero, so with many thin children the refiner asks the most unblocking
questions and leaves the rest to the comment path. The `--epic` form
reads `children/<child>.extract.md`, writes `children/<child>.refined.md`
and asks no consent question of its own; its readiness is re-scored from
that file. After the batch, one consent question:
`Apply the rewrites to <n> tickets (Recommended)` / `Keep them in the
comments only` / `Stop`. Apply → `tracker.update(child, description)` per
refined child, which counts as `--rewrite` for those children only. Unattended
or `off`: skip this block; the comment path below is unchanged.

Then, per child, unless offline:

- Gaps (any readiness other than `ready`, drafted criteria, inferred
  edges, open questions) → one owned comment through
  `tracker.comment(child, text)` after `voice.polish(text, durable)`,
  per **Owned comments** below. A child with no gaps gets no comment.
- `--rewrite` → `tracker.update(child, description)` with the enricher's
  `## Rewritten description`, only when that section exists. Never
  without the flag.
- Inferred edges → `tracker.link(a, blocks, b)` only when both ends are
  children of this container and no link of that type exists yet.
- A `rollout` child the enricher marks `split: proposed` (a configuration
  change plus a bake, see `work-types.md`) → collect into `E/plan.md`
  under `## Splits`. After all children: run the `ticket` gate from 4a
  over the splits batch, then `tracker.create` one `code` sibling per
  split (`parent: KEY`), link `code blocks <original>`, and treat the
  original as the `rollout` half. Nothing is created before the gate.

Re-runs: an enricher output younger than the child's last tracker update
is reused, not regenerated.

### 5. Graph

Build `E/graph.json` (shape in `epic-plan-template.md`):

- `nodes[]`: one per kept child (or plan ticket): `key`, `summary`,
  `work_type`, `size`, `status`, `ready`, `repo`, `blockers[]`,
  `gate_on_ready` (true for `decision` and `rollout`).
- `edges[]`: `{from, to, type}` where `type` is `blocks` for tracker links
  and `inferred` for edges the enricher found in text. Only edges with
  both ends in this container. A blocker outside the container goes into
  the node's `blockers[]` with its fetched status, not into `edges[]`.
- `soft[]`: `relates` links and "touches the same area" pairs; informative
  only.
- `cycles[]`: every cycle found by walking `edges[]`. Members of a cycle
  are never ready; `report.md` names the cycle and the edge that most
  likely should go (an `inferred` one first).
- `closeout` nodes get an edge from every other node (ordered last).
- Ready set: `status` is `open`, every key in `blockers[]` is `done` or
  `cancelled`, readiness is `ready`, and the node is in no cycle.

### 6. Route

Labels through `tracker.labels(child, add[])`, names from
`hygiene.md` only (the profile may rename them in `notes:`). Skip offline.
A `factory-mode:<mode>` label already on the child overrides the
enricher's work type.

| Work type | Labels | Factory behaviour |
|---|---|---|
| `code` | `factory-auto` | full loop when ready |
| `research`, `measure` | `factory-auto`, `factory-mode:<type>` | evidence comment when ready |
| `decision`, `rollout` | `factory-gated`, `factory-mode:<type>` | `gate_on_ready: true`: the heartbeat DMs a recommendation when blockers clear |
| `closeout` | `factory-auto`, `factory-mode:closeout` | runs after every other node |

A `rollout` that the enricher split keeps its labels; the new `code`
sibling gets `factory-auto`.

### 7. Report

Write `E/report.md`:

```markdown
# Factory plan: KEY — <title>
generated: <iso>   children: N   ready: R   blocked: B   gated: G   done: D
| Child | Type | Size | Status | Blockers | Route | Readiness |
|---|---|---|---|---|---|---|
| KEY-1 <summary> | code | M | open | – | auto | ready |
## Cycles            # only when graph.cycles is non-empty
## Open questions    # one line per child question, child key first
## Splits proposed   # only when any
```

Then, unless offline: `voice.polish(durable)` and post it as the
container's owned comment titled "Factory plan" (**Owned comments**);
`chat.dm` a four-line summary (ready, blocked, gated, questions) with the
report path. `E/status.json` `stage: planned`.

- `--run` → invoke `factory --epic KEY` (`--stack` passed through). The
  factory dispatches only the ready set and refreshes this comment on each
  tick.
- No `--run` → print the table and the command to start the factory.
- `--dry-run` → print the table and the list of writes that were skipped.

## Owned comments

Two comment titles are owned by this skill: "Pipeline readiness" on a
child, "Factory plan" on the container. The title is the comment's first
line. Before posting, read the ticket's comments and look for one whose
first line equals the title.

- None → `tracker.comment(key, text)`.
- Found and the profile's tracker `ops:` lists a comment update form →
  replace that comment's body.
- Found and no update form → post nothing when the body is unchanged;
  when it changed, post the new comment and record `gaps[]:
  "tracker: comment update unsupported; superseded comment left"`.

A comment never narrates the run. It states what is missing, what was
inferred, and what a reader should decide, so a lead can rank from the
first lines and the engineer who picks it up starts from the rest.

## Accounting

Every `Agent` call appends to `E/costs.json` and bumps
`status.json.costs.spawns`. Append `<iso> <stage> <event>` to `E/run.log`
at every step. The learner reads both.

## Harness notes

See `../pipeline/references/harness.md`. Without `Agent`, run the planner
and each enricher inline, one at a time, writing each output file before
the next; batches of five become sequential. Without `Skill`, read
`factory/SKILL.md` and follow it inline when `--run` is given. Without
`AskUserQuestion`, print the gate question and stop; the front door's
`KEY go` resumes.

## Hard rules

- Never create a ticket before the `ticket` gate, including split
  children. Never create anything when offline.
- Never rewrite a child's description without `--rewrite` or the human's
  `Apply` answer at the end of a refine interview, which covers only the
  children that interview rewrote.
- Never add a label outside `hygiene.md`'s list.
- Never move a child to another container, even when it belongs to a
  sibling's scope; flag it in the readiness comment.
- Idempotent re-runs update the same owned comments and never duplicate a
  ticket, a link or a label.
- Never name a vendor tool; every write goes through a capability and the
  profile.
- Prose that reaches people goes through `voice.polish` first.
