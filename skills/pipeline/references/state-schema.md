# State

All state lives under `$FACTORY_HOME` (default `$HOME/.factory`). It is never
committed. It survives worktree deletion and machine restarts because it sits
in the home directory. Every skill reads and writes here and nowhere else
outside the repository it is changing.

```
$FACTORY_HOME/
  config.json                 # see config-schema.md
  profile.md                  # see profile-schema.md
  _dashboard.md               # rendered by `pipeline dashboard`
  _heartbeat.json             # {last_tick, loop: started|manual|none, idle_since}
  _repos/<owner>-<repo>.md    # cartography cache, one file per repository
  _epics/<KEY>/               # epic-intake output
    context.md  plan.md  graph.json  children/<KEY>.md  children/<KEY>.refined.md  report.md
  _lessons/<date>-<KEY>.md    # learner output per run
  _lessons/INDEX.md           # fingerprint → count, first seen, last seen, status
  _factory/shift.json         # dispatcher state
  _chat/seen.json             # chat-intake watermarks per channel
  _self/<repo>/               # clones the learner edits to propose skill PRs
  _drafts/<slug>/             # a run before it has a tracker key
  tickets/<ID>.md             # file tracker (agnostic fallback)
  <KEY>/                      # one directory per run; KEY is the tracker key
    status.json
    run.log                   # append-only, one line per event: <iso> <stage> <event>
    costs.json                # [{stage, role, model, started, ended}]
    intake.md                 # the brief as understood, with acceptance criteria
    refine.md                 # ticket-refiner transcript and rewrite, when it ran
    refine/gaps.md            # gap-analyst output; refine/transcript.md during the interview
    sources/NN-<slug>.md      # fetched sources: url, fetched, extract, relevance
    context.md                # prepare output; round deltas appended
    train.json                # decomposer output when the ticket was split
    spec.md                   # verifier-safe spec (spec-format.md)
    spec-impl-notes.md        # builder-only implementation notes
    history/spec-round-N.md   # spec snapshot per round
    build/round-N/
      intent-checks.md  intent-gaps.md  spec-critique.md
      builder.md  qa.md  security.md  ux.md  mutation.md  burn-in.md
      summary.md  deferred.md  shots/
    verification/
      round-N-<persona>.md  round-N.md  ledger.json  deferred-findings.md
      scratch-round-N-<persona>/
    escalation.md
    pr.md                     # number, url, draft, body as published
    nurse/log.md  nurse/failure-N.md  nurse/ci-findings.md  nurse/review-findings.md
    sanity.md
    sentinel/log.md  sentinel/baseline.json  sentinel/anomaly-N.md
    research.md | measurement.md | recommendation.md    # non-code modes
```

## `status.json`

```json
{
  "key": "ABC-123",
  "profile": "vendor-a",
  "mode": "code",
  "epic": null,
  "stage": "prepare",
  "round": 1,
  "harness": "claude-code",
  "repo": {"path": "$HOME/work/repo", "remote": "owner/repo", "base": "main", "base_sha": null},
  "branch": {"name": "prefix-abc-123-slug", "pushed_sha": null},
  "ticket": {"url": "https://…", "summary": "…", "size": "M"},
  "children": [],
  "pr": {"number": null, "url": null, "draft": true, "merged_sha": null},
  "nurse": {"done": false, "passes": 0, "last_head": null, "retries": {}, "blocked": null},
  "review": {"last_seen": null, "open_items": 0},
  "sanity": {"verdict": null, "head": null, "body_hash": null, "checked_at": null},
  "sentinel": {"live_at": null, "window_end": null, "passes": 0},
  "gates": ["merge"],
  "pending_gate": null,
  "overrides": {},
  "instructions": [],
  "gaps": [],
  "lock": {"owner": null, "since": null},
  "costs": {"spawns": 0, "by_stage": {}, "wall_minutes": 0},
  "history": [{"ts": "…", "event": "created from /intake"}]
}
```

Field rules:

- `stage` ∈ `intake | prepare | spec | verify | pr | nurse | gated | merge |
  sentinel | incident | learn | done | escalated | stopped`.
- `mode` ∈ `code | research | measure | decision | rollout | closeout`.
  A container record under `_epics/<KEY>/status.json` uses `mode: epic`
  with stages `intake | gated | planned | dispatching | done | stopped`.
- `pending_gate` is the gate name while `stage == gated`, else `null`.
- `overrides{}` is written once by the front door at seed time and never
  changed. Keys the engine reads: `branch_prefix` (prepare), `comment_prefix`
  (review-nurse, pr-sanity-check), `connect` (the pr stage; `none` disables
  the profile's `connect:`). Each wins over config and the profile for this
  run only. The front door uses it for facts only it can know at seed
  time, such as which runner or worktree the session started in, so a run
  resumed elsewhere keeps the same branch name and prefixes. Anything that
  seeds a child run from a parent (the decomposer's split, `factory
  --stack`) copies the parent's `overrides` verbatim; a child never
  re-detects.
- `instructions[]` are strings appended by `<front door> KEY <text>`. Every
  stage reads them at start, applies what it can, and appends
  `applied: <text>` to `history[]`. They are never deleted.
- `gaps[]` lists capabilities that degraded during this run.
- `nurse.blocked` is `{reason, head, job, since}` while CI is broken by
  something other than this change, so the DM fires once per head and job.
- `sanity.head` and `sanity.body_hash` record what was checked; a new head
  or an edited body re-triggers the sanity check and resets `verdict`.
- Paths are stored with a literal `$HOME` and expanded on read, so the file
  stays valid when the home directory moves.
- If `repo.path` no longer exists on resume, recreate it: `git clone` or
  `git worktree add` from `repo.remote`, then `git checkout branch.name`
  from origin. Record the new path.

## Lock

A stage takes the lock by writing `lock.owner` (hostname and process or
session id) and `lock.since`. Another run refuses to proceed while a lock
is younger than 2 hours unless invoked with `--force`. Stages release the
lock on exit, including on error.

## Resumability

Every skill is single-pass and idempotent given `status.json`. Re-running a
stage after a crash either completes it or does nothing. Files are written
whole (temp file then rename) so a half-written artefact is never read.
