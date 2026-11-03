# Governor: models, budgets, accounting

## Models per role

`config.json.models` overrides any row. `inherit` means the model of the
calling session.

| Role | `model` |
|---|---|
| classifier judgement, spec-writer, intent-verifier, spec-critic, verifier (all personas), epic-planner | inherit |
| builder, qa, security, mutation-auditor, decomposer, researcher, measurer, retrospector | opus |
| cartographer, child-enricher, ux, sanity-reviewer, build-nurse, review-nurse, deploy-sentinel, factory, chat-intake, tick, discovery | sonnet |

## Budgets

`config.json.budget` defaults:

| Key | Default | Meaning |
|---|---|---|
| `max_rounds` | 5 | verifier rounds per run |
| `max_inner_passes` | 3 | builder fix passes inside one `spec-task` round |
| `max_agent_spawns` | 60 | `Agent` calls per run |
| `max_wall_minutes` | 240 | from the first `prepare` to CLEAN |

Exceeding any budget trips the valve (below, and `pipeline/SKILL.md`
"Valve"): the run escalates with the checkpoint attached.

## Valve

`pipeline/scripts/valve.sh <run dir>` evaluates the valve from the files
in a run directory and prints one line: `ok` (exit 0) or the reason of the
first condition that holds, in the order below (exit 3). Exit 2 means it
could not evaluate an input (stdout empty); the pipeline escalates then
too. N is `status.json.round`. A missing optional file (`verification/`,
`build/`, `nurse/`, `costs.json`, `run.log`, `config.json`) trips nothing;
one that is present but unreadable or malformed is exit 2. Fingerprints
are printed JSON-encoded. On exit 2, stderr names files inside the run directory
relative to it; the pipeline puts it in `run.log`, never in
`escalation.md` or a tracker comment.

| # | Trips when | Reason line |
|---|---|---|
| 1 | `round >= max_rounds` | `tripped: max_rounds round=N limit=M` |
| 2 | the same fingerprint in rounds N-1 and N after a fix attempt: an entry of `verification/ledger.json` with `status: open` whose `rounds` holds N-1 and N (the first key in byte order), else a `### F-` line of `nurse/ci-findings.md` in a `# CI findings round R` section with R = N-1 or N whose `repeat-of:` is set and not `none` | `tripped: repeat fingerprint="<fp>" source=ledger rounds=N-1,N`, else `tripped: repeat fingerprint="<fp>" source=ci-findings round=R` |
| 3 | the first `verdict:` line of `verification/round-<N-1>.md` and of `round-<N>.md` is `BLOCKED` | `tripped: blocked twice rounds=N-1,N` |
| 4 | the same with `INVALID` | `tripped: invalid twice rounds=N-1,N` |
| 5 | `build/round-N/builder.md` or a `build/round-N/builder-fix-*.md` has a line under `## Decisions needed` that is not blank or `none` | `tripped: decision needed round=N` |
| 6 | a budget is exceeded, checked as `max_agent_spawns`, then `max_wall_minutes`, then `max_inner_passes` | `tripped: budget <key> used=U limit=L` |

Budget limits, per key, first that is set: `status.json.budget.<key>` (a
per-run override; the pipeline writes it only from an `answer:`
instruction a human typed as `<front door> KEY <text>`, never from a
dedupe or chat-intake brief, a `sanity:` line or a stage agent), then
`budget.<key>` in the `config.json` beside the run directories (the run
directory's parent; the script does not read `FACTORY_HOME`), then the
default in the table above. A `status.json.budget.<key>` above twice the
`config.json` value (or the default when config has none) counts as twice
that value; going further needs a `config.json` edit. Used amounts and
comparisons:

- `max_agent_spawns`: the larger of `status.json.costs.spawns` and the
  number of `costs.json` entries (a JSON array, or one object per line);
  trips when used > limit.
- `max_wall_minutes`: the larger of `status.json.costs.wall_minutes`
  (floored) and the `wall=` of the last `run.log` checkpoint line; trips
  when used > limit. It is not derived from `costs.json` timestamps, which
  include time spent escalated or at a gate.
- `max_inner_passes`: the number of `build/round-N/fix-pass-*.md`; trips
  when used > limit, or used = limit and `build/round-N/summary.md` says
  `outcome: blocked` (the cap stopped the round with blocking findings
  open).

A run exactly at a spawn or wall limit, or at the inner-pass limit with
`outcome: complete`, prints `ok`.

## Accounting

Every `Agent` call appends one line to `<KEY>/costs.json`:

```json
{"stage": "spec", "role": "builder", "model": "opus", "started": "<iso>", "ended": "<iso>"}
```

`status.json.costs` keeps the totals (`spawns`, `by_stage`, `wall_minutes`).
After every round, append a checkpoint line to `run.log`:

```
<iso> checkpoint round=2 spawns=14/60 wall=58/240min inner=1/3
```

The final report and the dashboard show the last checkpoint. The learner
reads `costs.json` to report where time goes.
