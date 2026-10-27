# Thinness checks

A ticket is thin when a competent engineer with repository access could not
start without asking a question. These checks make that judgement
mechanical enough to be consistent and cheap enough to run on every brief.
Run them on human-written text only: the brief as typed, the ticket
description, its comments, and the fetched sources. A source can satisfy a
check the ticket itself does not. Text the factory produced (criteria
tagged `(inferred)`, `(drafted)` or `(assumed)`, `## Assumptions`, an
enricher's notes) never does, however good it looks; it is a guess, and the
interview exists to replace guesses with answers.

| Check | Fails when | Kind |
|---|---|---|
| T1 outcome | no sentence states what is observably different when the work is done (a behaviour, a number, a thing that exists or no longer happens). "Faster", "better", "cleaner", "works" without a measure do not count | blocking |
| T2 acceptance | no acceptance criterion can be read or inferred, or every candidate is unverifiable: "code is clean", "is refactored", "handles errors well", "is tested" | blocking |
| T3 problem | the problem statement is under 40 words after removing URLs and keys, and no source carries a problem statement either | advisory |
| T4 vague verb | the summary's main verb is one of: improve, fix (with nothing named as failing), look into, clean up, refactor, optimise, make better, handle, support (with no object), update, tweak, revisit | advisory |
| T5 decision | the text contains an unmade choice: "TBD", "either … or", "A or B", "depending on", "maybe", "not sure", "?" in the body, "we could" | blocking |
| T6 surface | no component, repository, service, path, page or user group is named, and the cartography cannot place the brief in one area | advisory |
| T7 container | the item is a container (level ≥ 1) with a description under 40 words and no children | blocking |
| T8 size | the brief names three or more surfaces, a migration, a flag plus a bake, or more than nine acceptance criteria, and does not say it is an epic | advisory; the decomposer will split, but asking now saves a round |

`blocking_failed` non-empty → interview under `refine.mode: auto`. Only
advisory failures → no interview; they become `## Assumptions` lines.

## Re-scoring after answers

Apply the same checks to the original text plus the transcript. An answer
counts as text. The interview stops when no blocking check fails and at
least three acceptance criteria exist that pass T2.

## Not thin

These do not fail any check, however short:

- A bug report with a reproduction and the observed and expected behaviour
  (T1 and T2 are satisfied by "expected").
- A ticket whose sources include a design or a decision thread that names
  the outcome and the scope; the gap-analyst quotes them under
  `## Already answered`.
- A `research` or `measure` ticket that states the question to answer and
  what form the answer takes (a comment, a page, a table). The outcome is
  the artefact.

## Signals that T1 passes

A sentence with any of: a number with a unit and a comparison; "no longer";
"a user can"; "returns"; "shows"; "is refused"; "exists at"; a named state
("Delivered", "enabled for 10%"); a named artefact ("a page under",
"a table of"). The gap-analyst quotes the sentence as evidence.
