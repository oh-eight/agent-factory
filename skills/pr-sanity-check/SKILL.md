---
name: pr-sanity-check
description: Checks that a pull request's title and body describe the diff it carries. A zero-context reviewer pre-registers what the diff must contain from the description alone, then reads the diff and reports MATCH or MISMATCHES, each tagged fix description or fix code. Invoked once by the heartbeat (`pipeline tick`) for a run in stage `nurse`, or by a front door given a PR; run by name only to debug one PR (`pr-sanity-check <PR number | PR url | KEY> [--comment]`).
argument-hint: "<PR number | PR url | KEY>"
metadata:
  tags: [factory, shipping, pr, review]
---

# PR sanity check

A PR body written by the same session that wrote the code reads as true to
that session whether or not it is. This skill hands the PR to a reviewer
that has seen nothing else, asks it to write down what the diff must
contain before it looks, then compares. It does not review code quality;
that is `review-nurse`'s and the humans' job.

Everything comes through the profile (`pipeline/references/capabilities.md`):
`pr.view`, `pr.reply`, `chat.dm`. The reviewer gets the profile's `pr` tool
line and reads the PR on its own.

## Workflow

```
- [ ] 1. Resolve the run and the PR
- [ ] 2. Early exits
- [ ] 3. Spawn the sanity reviewer with four inputs
- [ ] 4. Read sanity.md, record the verdict
- [ ] 5. Route: MATCH, fix description, fix code
- [ ] 6. Optional --comment
- [ ] 7. Close the pass
```

### 1. Resolve the run and the PR

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`.

| Input | Resolution |
|---|---|
| `KEY` | `$FACTORY_HOME/<KEY>/status.json` → `pr.number`, `repo.remote` |
| PR number or url (`…/<owner>/<repo>/pull/<n>`, `…/merge_requests/<n>`) | grep `$FACTORY_HOME/*/pr.md` for the number or url → the directory name is KEY |

`pr.view(n)` → `owner/repo`, number, title, body, `head_sha`, state, url.
Keep the body hash (`sha256` of the body text) for idempotency.

No `status.json` owns the PR → run in **detached mode**: output goes to
`$FACTORY_HOME/_drafts/sanity-<owner>-<repo>-<n>/sanity.md`, nothing is
written to any run, no DM. Say so in the first printed line.

### 2. Early exits

One line each, in order:

1. PR merged or closed → `PR-SANITY-CHECK: <pr> is <state>; skipped`.
2. `sanity.verdict` set and `sanity.head == head_sha` and
   `sanity.body_hash == body hash` → `PR-SANITY-CHECK: <KEY> already
   <verdict> at <sha7>` (pass `--force` to redo).
3. Profile `## pr` says `tool: none` → impossible; the run should not have
   reached `nurse`. Print the gap and stop.

### 3. Spawn the sanity reviewer

Role file: `agents/sanity-reviewer.md`. Model from `governor.md`
(`sanity-reviewer` → sonnet, overridable via `config.models`). Spawn per
`pipeline/references/harness.md`:

```
Agent(
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "sanity-reviewer for <owner/repo>#<n>",
  prompt: <full text of agents/sanity-reviewer.md>
          + "\n\n## Inputs\n"
          + "- pr: <n>\n"
          + "- repo: <owner/repo>\n"
          + "- pr_tool: <the `tool:` line of the profile's ## pr section, with the harness mcp_prefix when it is an mcp tool>\n"
          + "- output: $FACTORY_HOME/<KEY>/sanity.md\n"
)
```

Those four inputs and nothing else. No spec, no `intake.md`, no
`context.md`, no ticket text, no branch name, no state. The reviewer's
value is that it knows only what a stranger opening the PR would know. If
you are tempted to add context, the body should carry it instead.

Append `{stage: "nurse", role: "sanity-reviewer", model, started, ended}`
to `costs.json` and `costs.spawns += 1`. Wait for the agent to return.

### 4. Read sanity.md, record the verdict

Read `$FACTORY_HOME/<KEY>/sanity.md`. It must start with
`verdict: MATCH | MISMATCHES`; if it does not, or the file is missing,
re-spawn once with the same inputs, then record `sanity.verdict =
"INVALID"` and print the reason.

Set in `status.json`: `sanity.verdict`, `sanity.head = head_sha`,
`sanity.body_hash`, `sanity.checked_at`. Print the pre-registration table
and the mismatch list from the file (under one screen).

### 5. Route

**MATCH.** Log `sanity MATCH <sha7>` to `nurse/log.md`. No DM. Done; the
`pipeline` merge conditions read `sanity.verdict`.

**MISMATCHES.** Each mismatch in `sanity.md` carries `fix: description` or
`fix: code`. First, one `chat.dm` (`chat` register): PR url, counts of each
fix type, the one-line why of each mismatch, path of `sanity.md`. Then:

- Any `fix: code` → append to `nurse/review-findings.md` (create with the
  header if missing) one finding per item in the verification finding
  shape (`adversarial-review/references/report-template.md`), under a
  `## From pr-sanity-check (head <sha7>)` heading:

  ```markdown
  ### F-<round>-sanity-<i>  fingerprint: sanity-<slug>  repeat-of: none  personas: sanity-reviewer
  - claim: <C<n> when the mismatch names a promised behaviour, else `pr`>
  - category: implementation-bug | spec-gap
  - severity: medium
  - triage: loop
  - repro: <what the body promises and the command or path showing the diff lacks it>
  - observed: <what the diff has>
  - expected: <what the body says>
  ```

  Then `stage = prepare`, `round += 1`, append `{ts, event: "sanity fix
  code → prepare round N"}` to `history[]`, print
  `PR-SANITY-CHECK: FIX CODE → pipeline <KEY>`. The valve in `pipeline`
  applies as for any finding.
- Only `fix: description` → append to `instructions[]`: `sanity: update the
  PR body — <one line per item>`, set `stage = pr`, print
  `PR-SANITY-CHECK: FIX DESCRIPTION → pipeline <KEY>`. The `pr` stage runs
  its body step in update mode (`pr.edit`), then sets `sanity.verdict` to
  null so the next tick re-checks. Round does not change.
- Both kinds present → the code route wins; the description items ride
  along in `instructions[]` so the next `pr` stage fixes them too.

### 6. `--comment`

With `--comment` (never by default; the heartbeat does not pass it): post
`sanity.md` minus its `## Pre-registration` table as a top-level PR
comment through `pr.reply`, prefixed with `status.json.overrides.comment_prefix`
when set, else the profile's `comment_prefix`.
Skip if a comment with the same prefix and `head:` line already exists in
`pr.comments(n)`. In `config.offline` mode print it instead.

### 7. Close the pass

One line to `nurse/log.md`: `<iso> sanity <verdict> head=<sha7>
mismatches=<n> fix_code=<n> fix_description=<n>`. Write `status.json` whole
(temp file, then rename). The skill takes no lock; it edits only `sanity`,
`stage`, `round`, `instructions`, `costs` and `history`.

## Idempotency

Same PR, same head, same body → one printed line (step 2 rule 2). A new
push or a body edit re-runs the reviewer. The DM fires once per
(head, body) pair because the verdict is recorded with both. Findings are
appended once per head: check for an existing `## From pr-sanity-check
(head <sha7>)` heading before writing.

## Harness notes

- Without an `Agent` tool, do **not** run the reviewer in this session when
  the session wrote the code or the body: it has context the check is meant
  to exclude. Print the four inputs and ask the user to run
  `pr-sanity-check <n>` in a fresh session; that session, having no
  history, may follow `agents/sanity-reviewer.md` inline. If the user
  insists on running it here, follow the role file inline and set
  `context: same-session` in `sanity.md`; the dashboard shows that label.
- Without `Skill`, the heartbeat reads this file and follows it inline.
- `pr_tool` is whatever the profile says: an `mcp:` tool with its prefix or
  a `cli:` template. The reviewer uses it for `pr.view`, `pr.diff` and
  `pr.files` and nothing else.

## Hard rules

- The reviewer gets four inputs. Never add a fifth.
- Never judge code quality here; a mismatch is a gap between description
  and diff, not an opinion on the code.
- Never post to the PR without `--comment`; never DM on MATCH.
- Never call a vendor tool by name; the profile decides.
- Never write outside `$FACTORY_HOME`.
- One pass, one exit line, one log line.
