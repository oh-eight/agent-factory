---
name: prepare
description: First stage of the engine's code loop. Resolves the repository and branch for a ticket, maps the repository when the map is missing or stale, gathers the ticket, its sources and budgeted extra context into context.md, sizes the work and splits it into a ticket train when it is too large, routes prior-round findings, then hands over to spec-task. Invoked by `/intake` or `/intake-oss` through `pipeline` with a ticket key; run by name only to debug a run (`prepare KEY`).
argument-hint: "<KEY>"
metadata:
  tags: [factory, engine, stage, context]
---

# Implement

Turns a ticket into everything the spec-writer and builder need: a checked
out branch, a current map of the repository, and one `context.md` that
holds the ticket, its sources, the relevant code, related work and the
findings routed from the previous round. It never writes code. It ends by
invoking `spec-task`.

Read before acting: `pipeline/references/state-schema.md`,
`pipeline/references/capabilities.md`, `pipeline/references/sources.md`,
`pipeline/references/gates.md`, `pipeline/references/governor.md`,
`pipeline/references/hygiene.md`, `references/context-template.md`.

## Workflow

Copy this and track it:

```
- [ ] 1. Load state, config, profile
- [ ] 2. Resolve the repository
- [ ] 3. Resolve and check out the branch
- [ ] 4. Cartographer when the map is missing, stale or lacks the area
- [ ] 5. Fetch the ticket, comments, links; reuse intake.md and sources/
- [ ] 6. Budgeted extra context
- [ ] 7. Write context.md (round 1) or append the round delta (round N)
- [ ] 8. Decomposer: size, and split when L or XL
- [ ] 9. Hygiene: transition and comment on the first prepare
- [ ] 10. Invoke spec-task and check the stage on return
```

### 1. Load state, config, profile

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json` with
defaults from `config-schema.md`, then `profile.md`. Load
`$FACTORY_HOME/<KEY>/status.json`; missing means the front door did not
initialise this run: stop and say so. `N = status.round`. Read
`instructions[]` and note any that name a repository path, a branch, an
answer to an escalation, or a size override; apply them in the steps below
and append `applied: <text>` to `history[]`. Append
`<iso> prepare start round=N` to `run.log`.

Every write to `status.json`, `context.md` and `train.json` goes to a
`.tmp` file first, then `mv`.

### 2. Resolve the repository

Already in `status.json.repo.path` and the directory exists: use it. If the
path is gone, recreate it per `state-schema.md` (clone or `git worktree add`
from `repo.remote`, check out `branch.name` when it exists on origin).

Otherwise, in order, take the first that resolves:

1. The current working directory when `git rev-parse --show-toplevel`
   succeeds and the repository is not the one holding these skills.
2. `config.repos`: match the ticket's component, project or labels (from
   `tracker.get`) against its keys; the value is the path.
3. An instruction in `instructions[]` that names a path.
4. Ask once. Interactive: `AskUserQuestion` with the best guess first.
   Unattended: `stage: gated`, `pending_gate: repo`, `chat.dm` with the
   question and `<front door> KEY <path>` as the answer form, exit.

Record `repo.path` with a literal `$HOME`, `repo.remote` as `owner/repo`
parsed from `git remote get-url origin`, and `repo.base` from
`git symbolic-ref refs/remotes/origin/HEAD` (fallback `main`, then
`master`) unless the pipeline already set it (a train child inherits the
previous child's branch as its base). Run `git fetch origin` once.

### 3. Resolve and check out the branch

Prefix, first that is set: `status.json.overrides.branch_prefix` (the
front door stamps it at seed time for facts only it knows, such as which
runner the session is in), `config.branch_prefix`, the profile's `## pr`
`branch_prefix:`, else `<git user>/` from `git config user.name` lowercased
with spaces turned into hyphens.

Name: `<prefix><key-lower>-<slug>`. The slug is the ticket summary
lowercased, ASCII only, non-alphanumerics collapsed to one hyphen, cut at
40 characters without splitting a word. `branch.name` already in
`status.json` wins over a freshly computed name.

Check out, first that applies:

- Branch exists locally: `git checkout <name>`.
- Exists on origin only: `git checkout -b <name> origin/<name>`.
- Neither: `git checkout -b <name> origin/<repo.base>`.

Refuse to continue when `git status --porcelain` is dirty on a branch that
is not ours; say what is dirty and stop. Record `branch.name` and append
`<iso> prepare branch <name>` to `run.log`.

### 4. Cartographer

Map file: `$FACTORY_HOME/_repos/<owner>-<repo>.md` with `owner` and `repo`
from `repo.remote`. Area hint: the ticket's component field when present,
else the directories or module names named in the summary and description,
else the top-level directory the summary most plausibly touches.

Run the cartographer when any holds:

- the map file is missing;
- it has no `### <area>` heading matching the hint;
- that area's `mapped:` date is older than `config.cartography_ttl_days`.

Spawn per **Spawning roles** below with inputs `repo`, `area`,
`existing_map` (the path or `none`), `output` (the map path). The role
merges into the existing map and preserves `## Flake history`. On return
confirm the file has `## Repo`, `## Flake history` and the `### <area>`
section; otherwise re-prompt once with the missing section named.

### 5. Fetch the ticket, comments, links

Read the profile's `## tracker` and `## sources` sections first.

- `tracker.get(KEY)` for summary, description, acceptance criteria, type,
  component, labels, parent, links. Record `ticket.url` and
  `ticket.summary`.
- Comments through the same operation (or the profile's `ops:` line for
  comments). Keep decisions, constraints and corrections; drop noise.
- `intake.md` and `sources/` already exist when the front door wrote the
  brief. Read them; do not refetch any URL already in `sources/`.
- Every link in the description, comments and remote links that is not yet
  in `sources/` is fetched per `sources.md` and saved as
  `sources/NN-<slug>.md`, numbering continuing from the last file. Linked
  tickets are fetched with `tracker.get` plus comments. Failures become a
  stub file and a line under `## Open questions` in `context.md`.

When `intake.md` is missing (a run started from a bare key), write it now
from the ticket: summary, problem, acceptance criteria as observable
behaviours, links. Keep the acceptance criteria verbatim.

### 6. Budgeted extra context

Each capability is used only when the profile has a tool for it; `none`
means skip and append the capability to `status.json.gaps[]`. Every hit
that is kept gets a one-line relevance note; hits with no relevance to the
acceptance criteria are dropped, not listed.

| Capability | Queries | Keep at most | Looking for |
|---|---|---|---|
| `code.search` | up to 5: symbols, paths, flag names, error strings from the ticket | 10 files | where the behaviour lives; nearest existing pattern to copy |
| `pr.search` | up to 3: the key, the area, the main symbol | 5 PRs | recent changes to the same files; review themes; a reverted attempt |
| `tracker.search` | up to 2: same parent, same component or labels, open or recently done | 10 tickets | siblings that constrain the approach or share a surface |
| `knowledge.search` | up to 3: the feature or system name, the flag mechanism, the area's runbook | 5 docs | conventions, design docs, runbooks |
| `incidents.list`, `obs.alerts_firing`, `obs.logs_count` | only when the ticket or its comments use incident, alert, outage, error, regression, timeout or 5xx wording | 5 items | the signal the fix must move and its current baseline |

Stop a query family early once it stops producing new relevant hits. Run
the families in parallel when the harness allows. Record every query under
`## Related` so the next round does not repeat it.

### 7. Write context.md

Round 1: write `$FACTORY_HOME/<KEY>/context.md` whole from
`references/context-template.md`. Fill every section from steps 4 to 6;
leave `## Operational context` out unless step 6 gathered it. Acceptance
criteria are copied verbatim and numbered `AC-1`, `AC-2`, ... so claims
and intent checks can cite them.

Round N > 1: do not rewrite the file. Read, in this order, whichever exist:

- `verification/round-(N-1).md` (merged verdict and findings),
- `nurse/ci-findings.md`, `nurse/review-findings.md`,
- `sanity.md` when its verdict asked to fix code,
- `instructions[]` entries added since the last round (answers to an
  escalation count as findings of category `spec-gap`).

Classify every finding and route it:

| Category | Meaning | Route | What prepare does now |
|---|---|---|---|
| `env` | the verifier could not run or observe; setup, fixtures, commands wrong or missing | fix `## How to run` | re-check the cartography area's run and test commands, repair them in the map and in `## Codebase`; note the exact command that failed |
| `spec-gap` | behaviour the ticket wants but no claim covers, or a claim that says the wrong thing | spec-writer: new or changed claims | run one targeted step-6 pass on the gap (budget: 2 queries per family); write what the claim should say under the delta |
| `implementation-bug` | a claim is right and the code fails it | builder; claim unchanged | copy the repro verbatim; name the nearest entry point from the map |

A fingerprint that already appears in `verification/ledger.json` with
`status: open` for round N-1 is marked `repeat` in the table; the valve in
`pipeline` decides what that means, prepare only records it.

Append a `## Round N delta` section in the shape given in the template:
the classification table, then one short paragraph per `spec-gap` with
the proposed claim change, then any new sources or related items found in
the targeted pass. Append `<iso> prepare delta round=N findings=<count>`
to `run.log`.

### 8. Decomposer

Spawn per **Spawning roles** with inputs `context`, `intake`,
`cartography`, `output_dir` (`$FACTORY_HOME/<KEY>/`). Skip the spawn when
`status.json.ticket.size` is already set and `N > 1`, or when this run is
itself a train child (`status.json.epic` names a parent whose `train.json`
lists this key): record the size the parent gave it.

Return `S` or `M`: set `ticket.size`, continue to step 9.

Return `L` or `XL`: the role has written `split.md` and
`train.proposal.json`. Then:

1. Gate `ticket` per `gates.md`, showing `split.md`. Interactive: options
   `go`, `stop`, `other`. Unattended: `stage: gated`, `pending_gate:
   ticket`, `chat.dm`, exit. `other` with a merged or edited list means
   edit `split.md` and `train.proposal.json` to match before continuing.
2. `config.offline` true: do not create anything. Record `ticket.size`,
   add one line under `## Open questions` saying the split was proposed
   and skipped, continue as a single run.
3. For each child in order: `tracker.create` with the summary, description
   and acceptance criteria from `split.md`, the same project and issue
   type as KEY, the same component and labels, and `parent` set to KEY's
   parent when KEY has one, else to KEY (read the profile's `## tracker`
   `notes:` for how parents attach). Then `tracker.link(KEY, relates,
   child)`, and for each `blocks` edge in `split.md`,
   `tracker.link(a, blocks, b)`. Record each key as it is created so a
   crash leaves no orphans unrecorded.
4. Write `train.json`:

   ```json
   {"parent": "KEY", "children": [
     {"key": "KEY-201", "base_branch": "<repo.base>", "state": "pending"},
     {"key": "KEY-202", "base_branch": "<prefix>key-201-<slug>", "state": "pending"}
   ]}
   ```

   `base_branch` of the first child is `repo.base`; each next child's is
   the previous child's branch name computed by the step 3 rule. `state`
   is one of `pending | running | done | escalated`.
5. Initialise `$FACTORY_HOME/<child>/status.json` for each child from
   this run's file: same `profile`, `harness`, `mode`, `gates`,
   `overrides` (copied verbatim; children never re-detect), `repo`
   (with `repo.base` set to its `base_branch`), `epic` set to KEY,
   `stage: prepare`, `round: 1`, empty `branch`, `pr`, `nurse`,
   `review`, `sanity`, `sentinel`, `history` with one `created by
   prepare split of KEY` entry. Set `status.json.children[]` on KEY.
6. Hygiene comment on KEY naming the new keys and the order, through
   `voice.polish`. Append `<iso> prepare split children=<n>` to
   `run.log`. Return to `pipeline` without invoking `spec-task`; the
   pipeline runs the children in order. Say in the return that
   `train.json` exists.

### 9. Hygiene

Round 1 only, and only if `history[]` has no `transition in_progress`
entry: `tracker.transition(KEY, in_progress)` and one `tracker.comment`
per `hygiene.md` (branch, repository, sources not already on the ticket),
after `voice.polish(text, durable)`. Append the transition to `history[]`.
Rounds after the first add no comment; `pipeline` already commented the
findings. `config.offline` true: skip both and log the skipped text in
`run.log`.

Write `status.json` with `stage: spec`, the repo, branch and size fields
filled, and `costs` updated for every spawn.

### 10. Invoke spec-task

Invoke `spec-task KEY` with the `Skill` tool. On return read
`status.json.stage`: `verify` means success and prepare is done. Any
other stage (`gated`, `escalated`, `stopped`) is passed back to
`pipeline` unchanged with one line saying which. Never retry `spec-task`
from here.

## Spawning roles

Per `pipeline/references/harness.md`. `Agent` tool,
`subagent_type: general-purpose`, prompt = the full text of the role file
followed by an `## Inputs` block, one `- name: value` line per input,
every path absolute (expand `$FACTORY_HOME` and `$HOME` before passing).

| Role | File | `model` (governor.md) | Inputs |
|---|---|---|---|
| cartographer | `agents/cartographer.md` | sonnet | `repo`, `area`, `existing_map`, `output` |
| decomposer | `agents/decomposer.md` | opus | `context`, `intake`, `cartography`, `output_dir` |

`config.json.models` overrides the model. Append
`{stage: "prepare", role, model, started, ended}` to `costs.json` for
every spawn and bump `status.json.costs.spawns`. Each role returns under
30 lines; read its output file for detail, never ask it to repeat itself.

## Harness notes

Without `Agent`: read the role file, follow it in this session as that
role, write its output file, then continue with the next step. Without
`Skill`: read `spec-task/SKILL.md` and follow it inline at step 10.
Without `AskUserQuestion`: ask in plain text and stop; the answer arrives
as an instruction. Capabilities whose profile `tool:` is an MCP tool use
the prefix from the profile's `## Harness` section.

## Hard rules

- Never call a vendor tool by name; read the profile section for the
  capability and follow its `tool:` line.
- Never write code, tests or fixtures in the repository. Branch creation
  and checkout are the only repository writes.
- Never write outside `$FACTORY_HOME/<KEY>/`, `$FACTORY_HOME/_repos/`,
  the child run directories created in step 8, and the repository.
- Never create tracker tickets before the `ticket` gate passes, and never
  when `config.offline` is true.
- Never rewrite `context.md` after round 1; append a round delta.
- Acceptance criteria are copied verbatim, never paraphrased.
- Every kept search hit carries a relevance line; no bare link lists.
- Stay within the step 6 budgets; more context is not better context.
- Do not re-fetch a URL that is already in `sources/`.
- Hand over to `spec-task` exactly once per round, and only when
  `train.json` was not written in this round.
