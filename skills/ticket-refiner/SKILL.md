---
name: ticket-refiner
description: Interview the human to turn a thin brief or an empty ticket into something the factory can build, before any agent spends a round on it. Scores the text for missing outcome, acceptance criteria, scope or pending decisions, then asks up to five pointed questions with concrete options, and rewrites the ticket from the answers. Invoked by a front door (/intake or /intake-oss) on a thin brief, on `refine`, or by epic-intake on children marked needs-ac or needs-decision; run by name only to debug (`ticket-refiner <path-or-KEY> --dry-run`).
argument-hint: "<draft-dir | KEY> [--always] [--dry-run]"
metadata:
  tags: [factory, intake, refinement, interview, tracker]
---

# Ticket refiner

Most factory failures that reach the valve start as a ticket nobody could
have built from: "make uploads faster", an epic with a title and nothing
else, a one-line chat ask. The verifiers catch that four rounds later. This
skill catches it in the first minute, by asking the person who typed it.

It is an interview, not a form. Each question is one decision the factory
cannot make on its own, with two to four concrete options and the best guess
first, so answering is one keypress. It stops as soon as the ticket is
buildable or the human says "enough", and never asks what the sources
already answer.

Read before acting: `references/thinness.md`, `references/question-bank.md`,
`../pipeline/references/{harness,gates,config-schema}.md`, and the active
front door's `references/ticket-template.md` (the headings it rewrites to).

## Entry forms

```
ticket-refiner <draft-dir>                   a brief: $FACTORY_HOME/_drafts/<slug>/ holding intake.md and sources/
ticket-refiner <KEY>                         an existing ticket with a run: $FACTORY_HOME/<KEY>/
ticket-refiner <KEY> --epic <E> --rounds <N> a container child: _epics/<E>/children/<KEY>.extract.md; at most N questions; no consent question (epic-intake asks once for the batch)
ticket-refiner <target> --always             skip the thinness check; interview regardless
ticket-refiner <target> --dry-run            score and print the questions it would ask; ask nothing, write only refine.md
```

Config (`config-schema.md`): `refine.mode` `auto | always | off` (default
`auto`), `refine.max_rounds` (default 5), `refine.epic_rounds` (default 6,
shared across one container's children; epic-intake passes what is left as
`--rounds`).

## Workflow

Copy this and track it:

```
- [ ] 1. Load the text and decide whether to interview
- [ ] 2. Gap analysis → refine/gaps.md
- [ ] 3. Interview, one question per round, until buildable or enough
- [ ] 4. Rewrite the ticket body; write refine.md
- [ ] 5. Apply: draft in place | tracker.update behind consent | local only
```

`R` is the target directory (`_drafts/<slug>/` or `<KEY>/`). Files are
written whole (`.tmp` then `mv`). Nothing outside `R` and the tracker is
touched.

### 1. Load and decide

Collect two piles of text and keep them apart:

- **Original**: what humans wrote. For a draft, the `## Brief` section of
  `R/intake.md` and every `R/sources/*.md`. For a key, `tracker.get(KEY)`
  plus `tracker.comments(KEY)` (fetched into `R/sources/00-ticket.md` when
  not already there). For an epic child, `children/<KEY>.extract.md` and
  `_epics/<E>/context.md`.
- **Derived**: what the factory wrote about it. Everything else in
  `intake.md`, in particular criteria tagged `(inferred)`, `(drafted)` or
  `(assumed)` and the `## Assumptions` section; an enricher's
  `children/<KEY>.md`. Cartography
  (`$FACTORY_HOME/_repos/<owner>-<repo>.md`) when the brief or the cwd names
  a repository.

Score **only the original pile** with `references/thinness.md`. Derived
text never satisfies a check; a machine-drafted criterion is exactly the
guess this skill exists to replace with an answer. Derived text is passed to
the gap-analyst so its options can reuse good guesses. Then:

| Condition | Action |
|---|---|
| `refine.mode: off` and no `--always` | return `refine: skipped (off)` |
| `--always` or `refine.mode: always` | interview |
| `auto` and a blocking check fails | interview |
| `auto` and only advisory checks fail | no interview; list them under `## Assumptions` in `intake.md`; return `refine: not needed (advisory: T3, T6)` |
| nothing fails | return `refine: not needed` |

No way to ask (no `AskUserQuestion`, an `intake-context` trailer,
`config.offline`, or a dispatched run): do not interview. Run step 2 anyway,
copy its questions into `intake.md` under `## Open questions` with the best
guess marked `(assumed)`, append each to `config.json.pending_questions[]`
as `{key, question, guess, ts}`, set readiness `needs-ac` or
`needs-decision` where the front door or epic-intake records it, and return
`refine: deferred (N questions pending)`. This is exactly what the factory
did before this skill existed, so unattended behaviour does not change.

### 2. Gap analysis

Spawn `agents/gap-analyst.md` (model `sonnet`) with inputs `original` (the
human-written files, as paths), `derived` (the factory-written files, as
paths, or `none`), `cartography` (path or `none`), `thinness`
(path to `references/thinness.md`), `question_bank` (path to
`references/question-bank.md`), `template` (the front door's
`ticket-template.md`), `output: R/refine/gaps.md`. It writes: the check
results with evidence, the dimensions that are missing, and for each one a
ready-to-ask question with options and a recommended guess, ordered
blocking first. It also writes `## Already answered`: dimensions the
sources settle, with the quote, so the interview never asks them.

Without `Agent`, do the analysis inline and write the same file.

### 3. Interview

Rounds run in this session, because only it can ask. Cap: `--rounds N`
when given (epic-intake passes the remaining `refine.epic_rounds`), else
`refine.max_rounds`. Each round:

1. Take the first unanswered question from `gaps.md`, blocking ones first.
   Reword it against everything answered so far; drop it if an earlier
   answer settled it.
2. `AskUserQuestion` with one question: the recommended option first and
   marked `(Recommended)`, two or three alternatives that are concrete
   (never "something else", the tool adds Other itself), and as the last
   option `Enough, write it up with your best guesses`. For `outcome` and
   `verification` questions, options are candidate acceptance criteria
   written as observable sentences, with `multiSelect: true`.
3. Record the answer in `R/refine/transcript.md` as `Q<n>:` / `A<n>:`,
   with `(guess accepted)` when the recommended option was picked and
   `(free text)` when Other was used.
4. Re-score with `thinness.md` using the answers. Stop when every blocking
   check passes and at least three observable acceptance criteria exist,
   when the human picks `Enough`, or when the cap is reached. On the cap,
   the remaining blocking questions become `## Open questions` with the
   guess marked `(assumed)`.

In other harnesses print the question with its options and stop; the
answer comes back as `<front door> <target> <answer>` and the interview
resumes from the transcript.

### 4. Rewrite

Produce the ticket body in the front door's template headings from the
original text plus the answers. Rules:

- Nothing from the original is lost; moved or tightened is fine.
- Every answer lands somewhere: outcome → `## Problem` and `AC-1`; scope →
  `## Out of scope`; surfaces and constraints → `## Context` or `## Approach`
  (approach only when the human stated one); verification → `AC-n`;
  decisions → the chosen option in `## Approach`, the rejected ones in
  `## Out of scope`; anything still open → `## Open questions`.
- Acceptance criteria are present-tense observable sentences, numbered
  `AC-n`, with at least one negative case when input is validated or
  limited. A criterion the human did not state but accepted as a guess
  carries `(confirmed)`; an assumed one carries `(assumed)`.
- `## Assumptions` lists every guess taken without an answer.
- Summary under 80 characters, imperative, names the component when known.
- `voice.polish(body, durable)` once, after the fields are final.

Write `R/refine.md`:

```markdown
# Refine: <slug or KEY>
mode: auto | always   rounds: 3/5   result: buildable | enough | capped | deferred
checks before: T1 fail, T2 fail, T4 fail   after: all pass
## Transcript
Q1: … / A1: …
## Changes
- added AC-1..AC-4 (3 confirmed, 1 assumed)
- out of scope: …
## Summary
<the new summary line>
## Body
<the full rewritten body>
```

### 5. Apply

| Target | What happens |
|---|---|
| a draft (`_drafts/<slug>/`) | replace `intake.md`'s fields with the rewrite and record `refined: true` in it; the front door continues with dedupe, polish, gate and create as usual |
| a run with a hosted ticket (`<KEY>/`) | one last `AskUserQuestion`: `Apply the rewrite to KEY (Recommended)` / `Keep it local only` / `Stop`. Apply → `tracker.update(KEY, {summary?, description})` and one line in `history[]`; the summary changes only when the human picked an option that named a new one. Local → `intake.md` only. Never without the answer |
| a run with a file ticket | update `tickets/<KEY>.md` directly; the file tracker is local state |
| an epic child (`--epic <E>`) | write `_epics/<E>/children/<KEY>.refined.md` only; no consent question here. epic-intake applies it (its step 4b) after one consent question for the whole batch |
| `--dry-run` | write `refine/gaps.md` and `refine.md` with `result: dry-run`; nothing else |

Then return under 10 lines: result, `rounds_used: N` on its own line (the
caller subtracts it from a shared budget), checks before and after, the
count of acceptance criteria (confirmed, assumed), and the path of
`refine.md`.

## Harness notes

See `../pipeline/references/harness.md`. Without `Agent`, run the
gap-analyst inline. Without `AskUserQuestion`, this skill is the deferred
path of step 1 plus a printed first question; the front door's instruction
form carries answers back.

## Hard rules

- Never ask what a source already answers. `gaps.md`'s `## Already
  answered` section exists so this is checkable.
- One question per `AskUserQuestion` call, two to four options, the
  recommended one first, `Enough` always offered.
- Never write to a hosted tracker without the consent question in step 5.
  Drafts and file tickets are local state and need no consent.
- Never invent facts to fill a gap. A gap the human did not answer is an
  `(assumed)` line, visible in the ticket and in `## Assumptions`.
- Never run when the caller is unattended; defer, as step 1 says.
- Never name a vendor tool; the profile does that.

## Example

```
/intake-oss "make uploads faster"
  reading: 1 input: free text
  intent:  new (thin: T1 outcome, T2 acceptance, T4 vague verb)
  action:  refine (up to 5 questions), then draft in project UP

  Q1 Which upload path is slow?            → Browser uploads over 50 MB (Recommended) | API batch imports | Mobile | Enough
  Q2 What does "faster" mean when done?    → p95 under 5 s for 50 MB on the office network (Recommended) | …   [multiSelect]
  Q3 What is out of scope?                 → Resumable uploads (Recommended) | CDN changes | Mobile client | Enough
  Q4 How will you check it?                → Upload a 50 MB file; the progress bar reaches 100% within 5 s; a 2 GB file is refused with a message (Recommended) | …

  refine: buildable, 4/5 rounds, checks T1 T2 T4 → pass, AC 4 (3 confirmed, 1 assumed)
  → dedupe, draft, pipeline UP-41
```
