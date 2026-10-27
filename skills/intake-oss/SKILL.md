---
name: intake-oss
description: Agnostic front door of the factory. Takes anything (a sentence, a tracker key or URL, a chat permalink, a doc link, a PR or CI build URL with implementation intent, several of these on one line), works out what it is, turns it into pipeline-ready tickets and drives them through the engine. Discovers the tools on the machine on first run and asks only about the gaps. Use on "/intake-oss", "intake", "take this ticket", a pasted key or URL that should be built or shipped, or "what's the factory doing".
argument-hint: "[<anything> | <KEY> go|stop|<instruction> | tick | config [<text>]]"
metadata:
  tags: [factory, front-door, intake, agnostic, discovery]
---

# Intake (agnostic)

One command. You type a thing; the factory reads it, says what it understood,
creates or loads the tickets, and runs them. Called with nothing it shows the
dashboard and resumes whatever is waiting. It never names a vendor tool: the
profile written by discovery maps each capability to whatever this machine has,
and the engine (`pipeline` and the stage skills) reads the profile.

Read before acting: `references/grammar.md`, `references/classifier.md`,
`pipeline/references/capabilities.md`, `pipeline/references/profile-schema.md`,
`pipeline/references/state-schema.md`, `pipeline/references/gates.md`,
`pipeline/references/harness.md`. Read `references/discovery.md` when there is
no config yet or the argument starts with `config`. Read
`references/ticket-template.md` and `references/file-tracker.md` before
drafting a ticket.

## Workflow

Copy this and track it:

```
- [ ] 0. Home, harness, bootstrap when config.json is missing
- [ ] 1. Parse the argument with the grammar
- [ ] 2. Classify: kinds, then intent; print the reading
- [ ] 3. Act: resume | epic | new | batch
- [ ] 4. Ensure the heartbeat
```

### 0. Home, harness, bootstrap

```bash
FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"
mkdir -p "$FACTORY_HOME"
```

Detect the harness per `pipeline/references/harness.md`: `Agent` or `Skill`
visible → `claude-code` (a subagent may lack `AskUserQuestion` and is still
Claude Code); otherwise `cursor` or `codex` from the environment, and every
later step follows the sequential column. When no question can be asked
(no `AskUserQuestion`, an `intake-context` trailer, or `config.offline`),
every question below takes its recommended default and is written to
`config.json.pending_questions[]` for the dashboard.

If `$FACTORY_HOME/config.json` is missing, bootstrap:

1. Run discovery (`references/discovery.md`, all seven steps). It produces a
   candidate per capability, an auth state for each, and a list of gaps.
2. Ask one `AskUserQuestion` (one plain question in other harnesses) that
   batches only the gaps that change behaviour. Include a sub-question only
   when its condition holds:
   - tracker: two authenticated tracker candidates were found, or none. With
     none, the options are the repository host's issue tracker (when its CLI
     is authenticated) or the file tracker. Recommend the first that is
     authenticated.
   - chat notifications: a chat candidate exists. Yes or no.
   - unattended merge: always. "No" keeps the `merge` gate (default); "yes"
     sets `auto_merge: true` and removes `merge` from `gates`.
   No gap that changes behaviour → no question at all.
3. Write `config.json` (`pipeline/references/config-schema.md`) with
   `profile: "discovered"`, `front_door: "/intake-oss"`, the answers, and
   `discovery: {last: <iso>, ignore: [], answers: {…}}` so a later
   `config rediscover` does not ask again. Write `profile.md` exactly per
   `profile-schema.md`.
4. Print the profile summary: one line per capability (`tracker: cli:gh
   issue (auth ok)`), then `Gaps:` with what the factory does instead of each
   missing capability. Then continue with the argument the user gave.

Every later run loads `config.json` and `profile.md` and goes straight to 1.
If a capability call later fails with an unknown-tool error, rerun discovery
for that capability only and update the profile.

### 1. Grammar

`references/grammar.md` has the table. In short:

| Argument | Action |
|---|---|
| nothing | `pipeline dashboard` (renders `_dashboard.md`, prints it, resumes what is resumable) |
| `tick` | `pipeline tick` |
| `config` | print the effective config with the source of every value |
| `config <text>` | edit one key from the sentence per `config-schema.md`; show the diff first |
| `config rediscover` | rerun discovery, rewrite `profile.md`, print the summary and the diff against the old profile; reuse stored answers |
| `config ignore <family or server>` | add to `discovery.ignore`, then rediscover |
| `refine <input…>` | classify as usual, then `ticket-refiner --always` before the ticket is drafted or loaded |
| `<KEY> refine` | `ticket-refiner KEY --always` on an existing run's ticket; rewrite `intake.md`, then `pipeline KEY` with the instruction `ticket refined; re-read intake.md` |
| `<KEY> go` / `<KEY> stop` | gate behaviour from `pipeline/references/gates.md` |
| `<KEY> <text>` where `<KEY>/status.json` exists | append `<text>` to `instructions[]`, then `pipeline KEY` |
| anything else | an input: continue with 2 |

`<KEY>` is a tracker key in the profile's key syntax (`ABC-12`, `#12`,
`owner/repo#12`) or a file tracker key (`LOCAL-3`). A key with no run
directory is an input, not a command.

### 2. Classify

Follow `references/classifier.md`.

1. Pattern pass, deterministic: split the input on whitespace, match every
   URL and key against the pattern table and the profile's `## sources`
   hosts. Each token gets a kind: tracker item, container, chat thread, doc,
   PR, CI build, or free text (everything unmatched, joined back together).
2. Judgement pass: intent `new` (write a ticket), `resume` (an existing run,
   the user's own PR, or a build to nurse), `epic` (a container, or an L/XL
   brief), `batch` (several unrelated asks). Rules are in the classifier.
3. Print the reading before any write, in the three-line block from the
   classifier:

   ```
   reading: 2 inputs: tracker item ABC-12, chat thread (3 messages)
   intent:  new (ABC-12 is open with no run; the thread adds the brief)
   action:  draft ticket in project ABC, then pipeline
   ```

4. Ambiguous (two intents fit, the project cannot be inferred, a duplicate
   candidate was found) → one `AskUserQuestion` with the best guess as the
   recommended option. This is the only question allowed in the run apart
   from the refine interview (step 4, `new`), so bundle everything open
   into it. When the brief is thin, the reading's `intent:` line says so
   (`thin: T1 outcome, T2 acceptance`) and `action:` starts with `refine`.

### 3. Act

**resume**

- An existing run key → `pipeline KEY`.
- A CI build URL → find the PR it belongs to (profile `ci` notes, else the
  branch in the build), locate or seed the run, `build-nurse <url>`.
- The user's own PR (author equals `pr.view` viewer) with no run:
  - open → seed `status.json` at `stage: nurse` with the PR number, branch
    and repo, then `pipeline KEY`. KEY comes from the branch or the body;
    with none, `tracker.create` a ticket that summarises the PR (file
    tracker when that is the profile's tracker) so the key has a ticket
    behind it, then seed.
  - merged → nothing to nurse. Say so; when the profile has `deploy` or
    `obs`, offer `deploy-sentinel` on it as the one question, else stop.
  - closed without merge → stop and say so.
  Someone else's PR → it is a source for a new ticket, not a resume.
- A key-shaped token that neither the tracker nor the file tracker knows
  (`tracker.get` fails) is an `unknown key`: the reading says so, intent is
  ambiguous, and the one question is "typo, another tracker, or a new
  ticket with this text as the brief?". It never silently becomes a brief.

**epic**

- `tracker.hierarchy_level(KEY) >= 1` → `epic-intake KEY --run`.
- A brief judged L or XL from its sources → create a container ticket when
  the profile's tracker supports hierarchy (`notes:` says how children attach),
  else a parent file ticket (`type: container`), then `epic-intake KEY --run`.

**new**: the ticket writer, in this order.

1. Slug the brief (`kebab`, at most 40 chars); `mkdir -p
   "$FACTORY_HOME/_drafts/<slug>/sources"`.
2. Fetch every source per `pipeline/references/sources.md` into
   `_drafts/<slug>/sources/NN-<slug>.md`. Tracker items among the inputs are
   fetched with `tracker.get` plus comments. A failed fetch becomes a stub
   and a gap, not a stop.
3. Dedupe: `tracker.search` with the brief's distinctive words, same
   project, open or recently done. A match that asks for the same outcome →
   offer "resume <match>" as the recommended option in the one question.
   Taking it moves the fetched sources into `<match>/sources/` with the
   brief as one more source and deletes the draft; then, if
   `<match>/status.json` exists, append the brief to `instructions[]` and
   `pipeline <match>` without touching stage, round, branch, PR or
   `intake.md`; if not, run the existing-ticket path below. Dedupe runs
   before refine so an interview is never spent on a draft that is then
   dropped.
4. Refine: write a first `intake.md` with the user's words verbatim under
   `## Brief`, the sources, and any criteria you inferred under
   `## Acceptance criteria`, each tagged `(inferred)`. Then
   `ticket-refiner "$FACTORY_HOME/_drafts/<slug>"` (`--always` after the
   `refine` verb). Under `refine.mode: auto` it scores only the brief and
   the sources, never the inferred lines, and interviews when a blocking
   thinness check fails (`ticket-refiner/references/thinness.md`), up to
   `refine.max_rounds` questions, then rewrites `intake.md` from the
   answers. Unattended or offline it defers: questions land in
   `## Open questions` and `pending_questions[]`, and the run continues on
   best guesses as before.
5. Draft the fields from `references/ticket-template.md`: summary, problem,
   context with links, approach (only when a source carries one), out of
   scope, open questions, acceptance criteria as observable behaviours.
6. Infer project, issue type and work type per the template's rules. Work
   type sets `mode` (`code`, `research`, `measure`, `decision`, `rollout`).
7. `voice.polish(draft, durable)` (the profile's `voice` tool, or
   `pipeline/references/prose.md`).
8. Gate `ticket` if it is in `config.gates`: show the draft, wait for `go`.
9. Create: `tracker.create(fields)`; when the profile tracker is `file`, or
   `config.offline` is true, follow `references/file-tracker.md` instead.
   Record the returned KEY and URL.
10. `mv "$FACTORY_HOME/_drafts/<slug>" "$FACTORY_HOME/<KEY>"`. Update
    `intake.md` (the brief as understood, acceptance criteria as `AC-n`,
    sources, gaps, assumptions). Seed `status.json` per `state-schema.md`
    with `profile: "discovered"`, `mode`, `harness`, `stage: "prepare"`,
    `round: 1`, `gates` from config, `history: [{ts, event: "created from
    /intake-oss"}]`.
11. `pipeline KEY`.

**new from an existing level-0 ticket** (a key with no run): no draft dir,
no dedupe, no create. `mkdir -p "$FACTORY_HOME/<KEY>/sources"`, fetch the
ticket and its comments as sources, write `intake.md` from them (criteria
you draft are tagged `(drafted)`), then `ticket-refiner KEY` (auto mode
scores the ticket and sources only, so an empty or vague ticket gets the
interview; the consent question at its end decides whether the tracker
description is updated). Seed `status.json` as in step 10 with `history:
created from /intake-oss (existing ticket)`, then `pipeline KEY`.

**batch**: run the ticket writer once per ask (one reading block listing all
of them, one `ticket` gate showing all drafts). When the profile has
`dispatch`, every `tracker.create` in the batch adds the `factory-auto`
label (the one time a front door sets a label; `hygiene.md`), then
`factory --label factory-auto`. Without `dispatch`, no label; `pipeline KEY`
for each in order. Inputs that are shared context (a thread, a doc) attach
to every ticket's sources.

### 4. Ensure the heartbeat

Per `pipeline/references/heartbeat.md`, with the front door name
`/intake-oss tick`: check `_heartbeat.json`; if `loop` is not `started`,
start it (`loop` skill → `CronCreate` → print `/intake-oss tick` once and
record `loop: manual`). Do this after any action that leaves a run in
`nurse`, `sentinel`, `gated` or under a dispatcher.

### 5. Unattended callers

`chat-intake` and `factory` invoke this skill without a human typing. Their
brief ends with two trailer lines:

```
source: <permalink>
intake-context: <caller> channel=… thread=… author=… unattended=true auto=<bool> stop_after_ticket=<bool>
```

When `intake-context` is present: treat `source:` as a fetched source; never
call `AskUserQuestion` (an ambiguity returns instead of asking); gates follow
the unattended path in `gates.md`; `stop_after_ticket=true` ends the run
right after the ticket exists so the dispatcher picks it up from its label.
Return exactly one of these as the final line(s), nothing else after them:

```
ticket: KEY <url>              # one line per ticket for a batch or epic
ambiguous: <question>  guess: <best guess>
error: <one line>
```

## Harness notes

Without `Skill`, read `pipeline/SKILL.md` (and the stage skills it names) and
follow them inline. Without `Agent`, discovery and the classifier judgement
run in this session. Without `AskUserQuestion`, print the question and the
recommended answer, then stop; the user's reply comes back as
`/intake-oss <answer>` and the reading is recomputed with it. Without a loop
facility, print `/intake-oss tick` and ask the user to run it every 15
minutes.

## Hard rules

- Nothing is written to any tracker, chat or repository before the reading
  block is printed.
- At most one question per run, bootstrap included. Bundle. The one
  exception is the refine interview, which has its own cap
  (`refine.max_rounds`) and an `Enough` option on every question.
- `config.offline` true → every tracker operation goes to the file tracker,
  chat goes to the terminal, nothing leaves the machine except reads.
- Never name a vendor tool here or in the engine; the profile does that.
- Never write outside `$FACTORY_HOME` and the repository the engine is
  changing. Never edit the profile by hand from a stage; only discovery
  writes it.
- A key that the tracker does not know and the file tracker does not know
  is free text. Say so in the reading.

## Examples

```
/intake-oss
  → dashboard, then "resumed ABC-12 (lock expired)"

/intake-oss ABC-12
  reading: 1 input: tracker item ABC-12 (level 0, open, no run)
  intent:  new
  action:  intake.md from the ticket, status.json, pipeline ABC-12

/intake-oss https://chat.example/archives/C01/p1700000000 "add retries to the uploader"
  reading: 2 inputs: chat thread (7 messages), free text
  intent:  new (no open ticket matches "uploader retries")
  action:  draft ticket in project UP, gate ticket, then pipeline

/intake-oss owner/repo#88
  reading: 1 input: PR #88 by you, run REPO-14 found from the branch
  intent:  resume
  action:  pipeline REPO-14 (stage nurse)

/intake-oss "migrate the service to the new queue, with a staged rollout"
  reading: 1 input: free text, judged XL (3 surfaces, flag, bake period)
  intent:  epic
  action:  container ticket, then epic-intake --run

/intake-oss ABC-12 "use the existing retry helper, do not add a dependency"
  → appended to instructions[], pipeline ABC-12

/intake-oss "make uploads faster"
  reading: 1 input: free text (thin: T1 outcome, T2 acceptance, T4 vague verb)
  intent:  new
  action:  refine (up to 5 questions), then draft in project UP
  → four questions answered, intake.md rewritten with 4 criteria, pipeline UP-41

/intake-oss refine ABC-30
  → the ticket is loaded, the interview runs regardless of thinness, the
    rewrite is applied to ABC-30 after the consent question, pipeline ABC-30

/intake-oss config ignore hub          # a family name or an MCP server name
  → discovery.ignore updated, profile rewritten, summary printed
```
