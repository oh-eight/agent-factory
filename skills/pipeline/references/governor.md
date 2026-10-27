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

Exceeding any budget trips the valve (see `pipeline/SKILL.md`): the run
escalates with the checkpoint attached.

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
