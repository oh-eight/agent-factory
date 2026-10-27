# Ticket template

What the ticket writer drafts for intent `new`, in any tracker. The same
text is the body of a file ticket (`file-tracker.md`) and the description of
a hosted one. Headings stay; the tracker's own formatting is applied at
create time (the profile's `notes:` may say "markdown" or "wiki markup").

## Fields

| Field | Content | Rule |
|---|---|---|
| summary | one line, imperative, finishes "we need to …" | under 80 characters; names the component when known; no key, no prefix |
| problem | who is affected, what goes wrong or is missing, why now | two to four sentences from the sources; link the evidence inline |
| context | the links the user gave, each with one clause of what it holds | every input URL appears here; threads also get author and date |
| approach | how the sources say to do it | only when a source carries one (a thread decision, a doc proposal); never invented; quoted or paraphrased with the link |
| out of scope | what a reader might expect that this ticket does not do | at least one line; "nothing excluded" is not an answer when the sources mention adjacent work |
| open questions | what the writer could not settle from the sources | each with who could answer it when the sources say; empty is fine |
| acceptance criteria | observable behaviours, numbered `AC-1 …` | each is a sentence a stranger could check by running or looking, not "code is clean"; at least one negative case when the ticket validates or limits input |

The body, in this order:

```markdown
## Problem
…

## Context
- <url>: <what it is>

## Approach            <!-- only when a source carries one -->
…

## Out of scope
- …

## Open questions
- …

## Acceptance criteria
- AC-1: …
- AC-2: …
```

## Inference

### Project (or repository, for repository-hosted trackers)

In order; the first that yields a value wins:

1. A project key named in the brief or in a source ticket (`ABC-12` →
   project `ABC`).
2. The parent or sibling ticket's project when the brief references one.
3. `config.repos` mapping: a component named in the brief that maps to a
   repository whose tickets live in one project (learned from earlier runs,
   recorded in `_repos/<owner>-<repo>.md` under `## Repo`).
4. The current repository, for repository-hosted trackers and the file
   tracker.
5. `config.default_project`.
6. Ask, in the one question, with the most frequent project among recent
   runs as the recommended option.

### Issue type

Read the project's available types with `tracker.types(project)`, then pick
by cue:

| Cue in the brief or sources | Type |
|---|---|
| "broken", "fails", "regression", "error", "crash", a stack trace, an incident link | bug |
| "add", "support", "allow", "as a user" | story when the project has it, else task |
| "investigate", "find out", "measure", "decide", "write up" | task (work type carries the nuance) |
| the writer judged L or XL | the container type (epic, project, or `type: container` in the file tracker) |

When the project lacks the picked type, take the nearest the project has,
and say so in the reading's `action:` line.

### Work type

Same cues as `epic-intake`'s work types, because the two must agree:

| Work type | Cues | Mode set on the run |
|---|---|---|
| `code` | a behaviour to add, change or fix in a repository; default when nothing else fits | `code` |
| `research` | "investigate", "propose", "write a one-pager", "find out whether", "document" | `research` |
| `measure` | "measure", "baseline", "verify the savings", "how many", "dashboard the" | `measure` |
| `decision` | "decide", "choose between", "agree on", "sign off" | `decision` |
| `rollout` | "roll out", "enable for", "ramp", "bake", a flag plus a percentage | `rollout` (a config change plus a bake is split into `code` plus `rollout` by `epic-intake`) |
| `closeout` | "close out", "wrap up", "final report" | `research`, ordered last in an epic |

Record the work type as a label (`factory-mode:<mode>`) when the tracker has
labels, else in the file ticket's `type:` and `labels:` fields.

### Size

Count from the sources, the same way the decomposer does: surfaces, schema
changes, flags, cross-repo work, acceptance criteria. L or XL → intent
`epic`; the ticket writer drafts the container and `epic-intake` plans the
children.

## Dedupe

Before creating, `tracker.search` in the inferred project for open items
(and items done in the last 30 days) matching the summary's two or three
most distinctive words. For each hit compare outcome, not wording: if an
existing ticket would be satisfied by the same acceptance criteria, it is a
duplicate. Offer "resume <KEY>" (or "enrich <KEY> with this brief" when the
existing ticket is thinner) as the recommended option in the one question.
Hits that overlap partly are listed under `## Context` as related, with a
`relates` link after creation.

The file tracker searches front matter and bodies with `grep -il` over
`tickets/*.md`.

## Polish

`voice.polish(body, durable)` runs over summary and body once, after the
fields are final and before the `ticket` gate shows them. Headings and the
`AC-n` numbering never change.
