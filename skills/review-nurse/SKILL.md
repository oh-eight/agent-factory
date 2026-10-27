---
name: review-nurse
description: Answers and acts on human review comments on a factory PR. Invoked by the heartbeat (`pipeline tick`) while a run is in stage `nurse`, or by a front door after it opens the PR; run by name only to debug one pass (`review-nurse KEY`). Reads comments and reviews since the last pass, answers questions from the spec, fixes nits on the branch, routes behaviour changes and bugs into a new prepare round, and leaves disagreements open for a human.
argument-hint: "<KEY>"
metadata:
  tags: [factory, shipping, review, heartbeat]
---

# Review nurse

One pass over whatever reviewers said since the last pass. The nurse replies
in the reviewer's thread, changes only what is small and uncontroversial, and
turns everything else into a finding for the loop or a question for a human.
It never speaks for the reviewer: no resolving, no approving, no dismissing.

State lives in `$FACTORY_HOME/<KEY>/` (`pipeline/references/state-schema.md`).
Capabilities used: `pr.comments`, `pr.reviews`, `pr.reply`, `pr.edit`,
`chat.dm`, `voice.polish(chat)`. Read the profile's `## pr` section first
(`comment_prefix`, `body`, own login from the auth probe) and
`references/comment-classes.md` before classifying anything. Wherever this
skill says "the profile's `comment_prefix`",
`status.json.overrides.comment_prefix` wins when the front door set it for
this run.

## Workflow

Copy this and track it:

```
- [ ] 1. Resolve the run; bail out in one line when there is nothing to do
- [ ] 2. Fetch comments and reviews since review.last_seen; drop our own
- [ ] 3. Classify every new thread (comment-classes.md)
- [ ] 4. Act per class: answer, fix, route, or disagree
- [ ] 5. Changes-requested sweep: every thread has a reply
- [ ] 6. Update review.last_seen and review.open_items, log, summarise
```

### 1. Resolve

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json`,
`profile.md`, `<KEY>/status.json`. Print one line and stop when any holds:

- `status.json` missing, or `pr.number` null.
- `stage` is not `nurse`.
- `pr.merged_sha` is set, or the PR host reports the PR closed or merged when
  comments are fetched.
- The lock is held by someone else and younger than 2 hours.

Otherwise take the lock and append `<iso> nurse review-pass start` to
`run.log`. `config.offline` → read everything, write nothing to the PR, and
say so in the summary.

### 2. Fetch

`pr.comments(n, since=review.last_seen)` and `pr.reviews(n, since=review.last_seen)`.
A null `last_seen` means everything since the PR was opened.

Group comments by thread (a top-level review comment and its replies, or one
issue-level comment). Drop anything the factory wrote: author equals the own
login from the profile's `## pr` auth probe, or the body starts with the
profile's `comment_prefix`. A thread whose last comment is ours and has had
no reply is not new.

Nothing new and no `changes_requested` review outstanding → write the log
line (step 6) and stop with one line.

### 3. Classify

For each new thread, read the comment, the diff hunk it points at, `spec.md`,
`context.md` and the latest `build/round-N/summary.md`. Pick one class from
`references/comment-classes.md`:

| Class | Recognise it by |
|---|---|
| `question` | Asks why or how; no change requested |
| `nit` | Small code change, no behaviour change (naming, ordering, dead code, formatting) |
| `wording` | Text a person reads: PR title or body, code comments, docs, log and error messages |
| `behaviour` | Asks for different behaviour, reports a bug, or a nit that fails the "small" test |
| `disagree` | Asks for something the spec or ticket rules out |

Before acting on a thread, check that it does not already contain a factory
reply newer than the comment being handled. If it does, the previous pass
got this far; skip the action and keep the thread for the open-items count.

### 4. Act

Every reply goes through `voice.polish(text, chat)`, then gets the profile's
`comment_prefix` prepended, then `pr.reply(thread, text)`. Templates are in
`references/comment-classes.md`.

**question.** Answer from `spec.md` (quote the claim id), `context.md` or the
build summary. Cite the claim or the line of the ticket. When the answer is
not in those files, say what you do know and that the rest needs the author;
count the thread as open.

**nit.** Apply the "small" test from `comment-classes.md` (20 changed lines
or fewer, no behaviour change, no new dependency, files already in the
diff). Passes → in `repo.path` (recreate from `origin/<branch>` if missing),
`git fetch origin && git checkout <branch> && git pull --ff-only`, make the
edit, run the quick test command from `_repos/<owner>-<repo>.md` when it runs
in under a few minutes, commit `[KEY] <what changed> (review)`, `git push`.
Rejected push → fetch and retry once, never force. Reply with what changed
and the short sha. Fails the test → treat as `behaviour`, and say so in the
reply.

**wording.** Text in the diff → same as `nit`. Text in the PR title or body →
run the profile's `pr.body` in update mode (read the current body, change
only the section the comment is about, keep the author's edits), then
`pr.edit(n, title?, body?)`. Reply with the section that changed.

**behaviour.** Append a finding to `nurse/review-findings.md` in the shape of
`adversarial-review/references/report-template.md`:

```markdown
### F-<round+1>-R<k>  fingerprint: review-<thread id>-<slug>  repeat-of: none  personas: reviewer
- claim: C<n> | spec                       # the claim the comment contradicts, or `spec`
- category: implementation-bug | spec-gap  # bug in built code vs behaviour the spec never covered
- severity: high | medium
- triage: loop
- repro: <steps or input taken from the comment, made concrete>
- observed: <what the reviewer saw or expects to go wrong>
- expected: <what they asked for>
- source: <comment url>
```

Reply that it is being addressed in the next round. After the whole pass, if
at least one `behaviour` finding was appended: `stage: prepare`,
`round += 1`, append `history[]` `review findings → round N`, release the
lock, and send one `chat.dm` listing the findings and `pipeline KEY` as the
resume command. The pipeline's valve applies when the round starts.

**disagree.** Reply with the reasoning and the exact spec claim or ticket
line that rules the request out. Leave the thread open. Count it in
`review.open_items`. Do not implement it, do not file a finding.

### 5. Changes-requested sweep

If any `pr.reviews` entry since `last_seen` has state `changes_requested`:
list every unresolved thread on the PR (not only the new ones). Any thread
whose last comment is not ours gets handled by steps 3 and 4 now. The review
itself is not dismissed; the reviewer re-reviews.

### 6. Update state, log, summarise

- `review.last_seen` = the newest `created_at` among the comments and reviews
  fetched in step 2 (set only after the actions above, so a crash mid-pass
  replays the pass; the idempotency check in step 3 makes the replay safe).
- `review.open_items` = unresolved threads whose last comment is not ours,
  plus `disagree` threads, plus `question` threads answered with "needs the
  author".
- Append to `nurse/log.md`:
  `<iso> review pass=<n> new=<k> question=<a> nit=<b> wording=<c> behaviour=<d> disagree=<e> open_items=<o> stage=<stage>`
- `run.log`: `<iso> nurse review-pass end`. Release the lock.

Print five lines: PR and head sha; threads seen and per-class counts; what
was pushed or edited (shas, sections); findings routed and the new round, or
"none"; `open_items` and what a human still owes.

## Harness notes

Without `Skill`, read the profile's `pr.body` skill file and follow it inline
for body updates. Without `Agent`, nothing changes: this skill never spawns.
When the heartbeat spawns the pass as a subagent it uses the `review-nurse`
row of `pipeline/references/governor.md` (sonnet) and passes `KEY` and
`FACTORY_HOME` in the `## Inputs` block.

## Hard rules

- Never resolve a thread, approve, request changes, dismiss a review, edit
  or delete anyone else's comment, or merge.
- Never force-push. Never rewrite history on the branch.
- Never change behaviour under the `nit` or `wording` class; route it.
- Never implement a `disagree` request to make the thread go quiet.
- Never reply without the profile's `comment_prefix`; reviewers must be able
  to tell the factory from the author.
- Never name a vendor tool; every call goes through the profile.
- One DM per pass at most, and only when the stage changed.
