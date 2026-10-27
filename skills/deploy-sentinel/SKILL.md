---
name: deploy-sentinel
description: Watches a merged factory change after it goes live. Invoked by the heartbeat (`pipeline tick`) while a run is in stage `sentinel`, or by a front door right after the merge; run by name only to debug one pass (`deploy-sentinel KEY`). Waits for the deploy, takes a baseline from the hour before, compares error ratio, tail latency, error logs, firing alerts and incidents against it on every pass, and on an anomaly writes the evidence with a prepared revert and hands the run to a human.
argument-hint: "<KEY>"
metadata:
  tags: [factory, shipping, deploy, observability, heartbeat]
---

# Deploy sentinel

One pass per heartbeat during the post-deploy window. The sentinel reads,
compares, and writes files; it never changes production. The only outward
actions are one DM on an anomaly and the stage change that stops the run
until a person looks.

State lives in `$FACTORY_HOME/<KEY>/` (`pipeline/references/state-schema.md`),
with this skill's files under `<KEY>/sentinel/`. Capabilities used:
`deploy.live_status`, `obs.alerts_firing`, `obs.logs_count`,
`obs.metrics_range`, `obs.explore_link`, `incidents.list`, `chat.dm`. Read
the profile's `## obs`, `## deploy` and `## incidents` sections and
`references/signals.md` before the first query.

## Workflow

Copy this and track it:

```
- [ ] 1. Resolve the run; degrade or bail out in one line when there is nothing to do
- [ ] 2. Wait for live (or take the merge time); fix live_at and window_end
- [ ] 3. Resolve the service and the signal queries
- [ ] 4. Baseline once: the same signals for the hour before live_at
- [ ] 5. Pass: last 15 minutes against baseline and thresholds
- [ ] 6. Anomaly → anomaly-N.md, stage incident, DM; window over → HEALTHY, stage learn
- [ ] 7. Log the pass, print the summary
```

### 1. Resolve

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json`
(`sentinel.window_minutes`, default 120), `profile.md`, `<KEY>/status.json`.
Print one line and stop when `status.json` is missing, `stage` is not
`sentinel`, `pr.merged_sha` is null, or the lock is held by someone else and
younger than 2 hours. Otherwise take the lock and append
`<iso> sentinel pass start` to `run.log`.

Degradation, in this order:

- `obs` is `tool: none` → append `obs: sentinel skipped` to `gaps[]`,
  `stage: learn`, log line, print `sentinel skipped: no observability`, stop.
- `deploy` is `tool: none` → the window starts at merge time (step 2);
  append `deploy: window from merge time` to `gaps[]` once.
- `incidents` is `tool: none` → omit the incident signal; append
  `incidents: not checked` to `gaps[]` once.

### 2. Live

When `sentinel.live_at` is null:

- `deploy` present → `deploy.live_status(pr.number)`. Not live → log line
  `waiting for deploy`, `sentinel.passes += 1`, print one line, stop. Still
  not live 24 hours after the merge → `gaps[]` `deploy: never reported live`,
  `stage: learn`, stop with one line. Live → `live_at` = the `at` field of
  the response (now if absent), record `version` in the log line.
- `deploy` absent → `live_at` = the time of the `merge` entry in
  `history[]`, else `git show -s --format=%cI <merged_sha>` in `repo.path`.

`sentinel.window_end = live_at + sentinel.window_minutes`. Write `status.json`
whole.

### 3. Service and queries

Resolve, in this order, and stop at the first source that names a service:
the profile's `## obs` `notes:` (metric names, label names, service, log
field names, pre-built queries), the `## Repo` deploy section of
`_repos/<owner>-<repo>.md`, then `context.md`. Fill the placeholders of every
signal in `references/signals.md` (its `## Profile overrides` section says
which names the profile may replace; `## Learned` rows for this service win
over defaults). No service name from any source → `gaps[]`
`obs: no service name`, `stage: learn`, print `sentinel skipped: no service
name`, stop.

### 4. Baseline

Once, when `sentinel/baseline.json` does not exist: run every resolved signal
for `[live_at - 60m, live_at]` and store, per signal, the resolved query, the
value (mean over the hour at 5-minute steps for ratios and quantiles; hourly
count divided by four for log counts; the list of alert names firing; the
list of open incident ids), and the request rate for the low-traffic rule.
Write whole (`.tmp` then `mv`). A query that errors stores `null` with the
error text; that signal is reported as unavailable, not as healthy.

### 5. Pass

Window `[max(now - 15m, live_at), now]`. For each signal:

| Signal | Call | Compare |
|---|---|---|
| error ratio | `obs.metrics_range(ratio query, from, to, 1m)` | mean vs baseline: over when > 2x and > 0.5 percentage points absolute |
| p95 latency | `obs.metrics_range(p95 query, from, to, 1m)` | mean vs baseline: over when > 1.5x, and marked over in the previous `sentinel/log.md` line too |
| error logs | `obs.logs_count(error query, from, to)` | over when > 2x the baseline per-15-minute count and at least 10 lines more, two passes running |
| alerts | `obs.alerts_firing(service)` | over when any alert fires that is not in the baseline list |
| incidents | `incidents.list(service, since=live_at)` | over when any incident is open or was opened after `live_at` |

Thresholds, the low-traffic rule, and the consecutive-pass rule are
authoritative in `references/signals.md`; the table above is the default.
Any signal over its threshold (with the consecutive rule satisfied) is an
anomaly. Signals returning `null` are listed as unavailable in the log line.

### 6. Verdict

**Anomaly.** `N` = number of existing `sentinel/anomaly-*.md` + 1. Write
`sentinel/anomaly-N.md`:

```markdown
# Anomaly N — KEY
detected: <iso>  live_at: <iso>  pass: <n>  merged_sha: <sha>  pr: <url>
## Signals over threshold
| signal | baseline | now | threshold | link |         # link from obs.explore_link(query)
## Other signals this pass
<one line each, with values, so a reader sees what was normal>
## Suspected relation to the change
<Which changed areas (context.md module map, build summary) touch the service
or labels that moved. Say "weak" when the change does not touch the signal's
code path; a coincident deploy of something else is possible.>
## Prepared revert (not executed)
git fetch origin && git checkout -b revert-<key-lower> origin/<base>
git revert <merged_sha>                     # add `-m 1` when merged_sha has two parents
git push -u origin revert-<key-lower>
pr.create(base=<base>, head=revert-<key-lower>, title="Revert [KEY] <title>", body=<this file's first two sections>, draft=false)
                                            # as the profile's `pr` tool spells it, when it is a cli: form
## What a human decides
revert, roll forward, or watch; incidents open; who was paged
```

Then `stage: incident`, `history[]` `anomaly N: <signals>`, one `chat.dm`
with the signal table, the explore links, the anomaly file path, and the
revert branch name. Release the lock, stop. Never run the revert.

**Window over.** `now >= window_end` and no anomaly → print
`DEPLOY-SENTINEL: HEALTHY`, `stage: learn`, `history[]` `sentinel healthy
after <passes> passes`. No DM: the run's final report and the heartbeat's
`done` message carry the verdict.

**Otherwise** the pass ends and the next heartbeat runs the next one.

### 7. Log and summary

Append to `sentinel/log.md` every pass, including waiting and skipped ones:

```
<iso> pass=<n> state=waiting|baseline|watch|anomaly|healthy|skipped error_ratio=<now>/<base>[!] p95=<now>/<base>[!] error_logs=<now>/<base>[!] alerts=<count>[!] incidents=<count>[!] unavailable=<list> remaining=<minutes>
```

`!` marks a signal over its threshold this pass; the next pass reads these
marks for the consecutive rule. `sentinel.passes += 1`. `run.log`:
`<iso> sentinel pass end <state>`. Release the lock.

Print five lines: service and version watched; live_at, window_end, minutes
remaining; each signal as now/baseline; verdict (`watching`, `HEALTHY`,
`ANOMALY N`, or skipped with the reason); anomaly file and DM sent, or
"none".

## Harness notes

Nothing in this skill needs `Agent` or `Skill`. Without a `loop`, the
heartbeat is run by hand (`<front door> tick`); every pass is complete on its
own and safe to repeat. When the heartbeat spawns the pass as a subagent it
uses the `deploy-sentinel` row of `pipeline/references/governor.md` (sonnet)
with `KEY` and `FACTORY_HOME` in the `## Inputs` block. `config.offline`
means no DM; the anomaly file is still written.

## Hard rules

- Read-only against production: never run a revert, a rollback, a scale
  change, or any deploy command. The revert is text in a file.
- Never silence, acknowledge, or resolve an alert or incident.
- Never declare HEALTHY while a signal is unavailable for the whole window;
  record the gap and say so in the summary and the final report.
- Never compare against a baseline from a different service or a window that
  overlaps the deploy.
- Never name a vendor tool, metric, or dashboard in this skill; names come
  from the profile, cartography, and `references/signals.md`.
- One DM per run at most from this skill, on the anomaly only.
