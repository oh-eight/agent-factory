# Grammar

Everything after `/intake-oss` is one argument string. The first token that
matches a form below decides what happens; the rest of the line belongs to
that form. Several inputs on one line are allowed and are classified
together.

| Form | What happens |
|---|---|
| `/intake-oss` | `pipeline dashboard`: render `_dashboard.md`, print it, resume runs whose lock expired or whose gate received an instruction |
| `/intake-oss <input…>` | classify (kinds, then intent), print the reading, create or load tickets, run `pipeline KEY` for each |
| `/intake-oss <KEY> go` | the pending gate on KEY passes: clear `pending_gate`, restore the guarded stage, `pipeline KEY`. On a `stopped` run, reopen it |
| `/intake-oss <KEY> stop` | `stage: stopped`; the heartbeat skips it until `go` |
| `/intake-oss <KEY> <instruction>` | append the text to `status.json.instructions[]` with a timestamp in `history[]`, then `pipeline KEY`; the next stage reads and applies it |
| `/intake-oss tick` | one heartbeat pass (`pipeline tick`) |
| `/intake-oss config` | print the effective `config.json` with defaults filled in and the source of each value (default, file, learned on date) plus the profile summary |
| `/intake-oss config <text>` | edit one key from a sentence ("default project VE", "gates spec,merge", "turn mutation off", "parallel 3"); print the diff, then write |
| `/intake-oss config rediscover` | rerun discovery, rewrite `profile.md`, print the summary and what changed; stored answers are reused, so no question unless a new gap appeared |
| `/intake-oss config ignore <name>` | add a tool family or MCP server name to `config.discovery.ignore`, then rediscover |
| `/intake-oss refine <input…>` | classify as usual, then run the `ticket-refiner` interview regardless of thinness before the ticket is drafted or loaded |
| `/intake-oss <KEY> refine` | interview on an existing run's ticket; rewrite `intake.md` (and the tracker description after consent), then `pipeline KEY` |

## Resolving `<KEY>`

A first token is a `<KEY>` command only when `$FACTORY_HOME/<KEY>/status.json`
exists. Key syntaxes the front door recognises:

| Syntax | Where it comes from |
|---|---|
| `[A-Z][A-Z0-9]+-\d+` | project-keyed trackers and the file tracker (`LOCAL-n`) |
| `#\d+` | the issue tracker of the current repository (the run directory is named `<owner>-<repo>-<n>`) |
| `owner/repo#\d+` | the same, fully qualified |

Keys with no run directory are inputs: the classifier fetches them and the
ticket writer decides whether to resume, enrich or create.

## Precedence

1. Empty → dashboard.
2. First token is exactly `tick`, `config` or `refine` → that form.
3. First token is a key with a run directory and the second token is `go`,
   `stop` or `refine` and nothing follows → gate form (or refine form).
4. First token is a key with a run directory and more text follows →
   instruction form.
5. First token is key-shaped, has no run directory, and the second token is
   exactly `go` or `stop` → error: print `no run for <KEY>` and the
   dashboard. Never a ticket.
6. Anything else → input.

`go` and `stop` as the whole argument with no key are inputs (free text);
the classifier will ask which run was meant if more than one is gated.
`refine` alone is an error: print the two refine forms and the dashboard.
`<KEY> refine` for a key with no run is the same as `refine <KEY>`.

## Instructions

An instruction is free text. Stages read all of them at start and apply what
they can. Conventions the stages understand without judgement:

| Instruction text | Effect |
|---|---|
| `gates spec,merge` | per-run gate list |
| `repo <path>` | repository to use for this run |
| `base <branch>` | base branch |
| `skip <role>` | do not run that role this round (verifiers cannot be skipped) |
| `answer: <text>` | the answer to an escalation question |
| anything else | read by the next stage as guidance; recorded in `history[]` as `applied:` when honoured |
