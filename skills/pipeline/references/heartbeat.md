# Heartbeat (`<front door> tick`)

One recurring pass drives everything that waits on the outside world: CI,
human review, deploys, dispatch slots, chat channels. There is one loop per
machine, not one per PR.

## Starting it

The front door starts the loop the first time a run reaches a stage that
needs it (`nurse`, `sentinel`, an open shift, a configured chat channel):

1. `loop` skill available → invoke it with `15m <front door> tick`.
2. Else `CronCreate` with the prompt `<front door> tick` every 15 minutes.
3. Else print the command once and write `loop: manual` to
   `_heartbeat.json`.

Record `loop: started` and never start a second one; check
`_heartbeat.json` first.

## One pass

1. Read `_heartbeat.json`, `config.json.heartbeat` (intervals per pass
   type: `nurse` 15, `sentinel` 15, `factory` 30, `chat` 30 minutes).
2. For every `<KEY>/status.json` with stage not in
   `done | escalated | stopped`, using the profile stamped on that run:
   - `nurse` → run `build-nurse` and `review-nurse` passes if their
     interval elapsed; run `pr-sanity-check` once if `sanity.verdict` is
     null.
   - `sentinel` → run a `deploy-sentinel` pass.
   - `learn` → run `learner`.
   - `gated` or `escalated` with a new instruction since the gate → resume
     the run (`pipeline KEY`).
   - `prepare` or `pr` reached from a nurse pass (CI findings, review
     findings, a sanity verdict) and no live lock → resume the run
     (`pipeline KEY`) so the next round starts without a human.
   - any stage with an expired lock (older than 2 hours) and no progress →
     resume the run.
3. `_factory/shift.json` open → run a `factory` pass (fill slots,
   re-evaluate epic ready sets).
4. `config.json.chat_channels` non-empty → run a `chat-intake` pass.
5. Write `_dashboard.md` (see `dashboard.md`) and update
   `_heartbeat.json.last_tick`.
6. Send one `chat.dm` only if a run changed to `nurse: green`, `gated`,
   `escalated`, `merge`, `incident` or `done` during this pass; one message
   listing all changes.
7. Nothing active → print one line, set `idle_since` if unset. After 24 h
   idle, remove the loop (`loop` skill stop, or the cron entry) and set
   `loop: none`.

A pass is idempotent: running it twice in a row changes nothing the second
time. Every sub-pass is the existing single-pass skill; `tick` only decides
what is due and in which profile.
