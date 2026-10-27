# Question bank

Dimensions the interview may ask about, in the order they usually unblock
a build. Each entry says what the question is for, how the gap-analyst
builds concrete options, and where the answer lands in the ticket. The
analyst rewrites every question for the ticket at hand; these are the
shapes, not the words.

| Dimension | Triggered by | Question shape | Option source | Feeds |
|---|---|---|---|---|
| `surfaces` | T6 | Where does this live? | components, services or pages from the cartography and the text; the repository the cwd is in | context |
| `outcome` | T1 | When this is done, what is observably different? | candidate acceptance criteria built from the text's nouns and the sources' numbers; present tense; one behaviour each; `multi: true` | problem, AC |
| `users` | T1 or T3 with no actor named | Who hits this? | user groups or callers named in the sources; "internal tooling" and "public API" as generic fallbacks | problem |
| `decision` | T5 | The text leaves a choice open: which way? | the options as the text states them, plus the one the sources lean towards marked as the guess | approach, out_of_scope |
| `scope` | T8, or a brief that touches an adjacent feature | What is explicitly not part of this? | adjacent features and follow-ups the text or sources mention; `multi: true` | out_of_scope |
| `constraints` | security, data or performance wording without a bound | What must not change or break? | compatibility, limits, auth boundaries, data retention from the sources; cartography's flag mechanism | AC (negative cases), context |
| `verification` | T2 after `outcome` is answered | How would you check it by hand? | commands, requests or clicks a stranger could perform, derived from the outcome answer and `## How to run` in the cartography; `multi: true` | AC |
| `failure` | input validation or limits in the text | What happens on bad or oversized input? | refuse with a message; accept and truncate; accept silently; the sources' current behaviour as the guess | AC (negative case) |
| `size` | T8 | Is this one ticket or a container? | one ticket now, the rest later (guess when under three surfaces); a container with these children (listed); | decision on intent `epic` |
| `rollout` | a flag, a percentage or "enable for" in the text | How does it go out and come back? | behind a flag with a bake; straight to everyone; staged by region or cohort; revert path | approach, AC |
| `done_form` | `research`, `measure`, `decision` work types | What form does the answer take? | a comment on the ticket; a page; a table with these columns; a recommendation with options | AC (the artefact) |

## Rules for options

- Two to four. The first is the analyst's best guess with a one-clause
  reason. The interview appends `Enough, write it up with your best
  guesses` itself.
- Concrete: a name, a number, a behaviour. "Depends" is never an option.
- Mutually exclusive unless `multi: true`.
- Drawn from the text, sources or cartography wherever possible, each with
  a pointer. Generic fallbacks are marked `(generic)` and used only when
  the text offers nothing.

## Acceptance criteria options

For `outcome`, `verification`, `failure` and `constraints`, every option is
a complete criterion a stranger could check, in the shape the spec writer
will turn into a claim:

```
A 50 MB file uploads from the browser in under 5 s on the office network.
Uploads over 2 GB are refused before any bytes are sent, with a message naming the limit.
An interrupted upload leaves no partial object in the bucket.
```

Three accepted options from these dimensions usually end the interview.

## Questions never asked

- Anything `## Already answered` in `gaps.md` covers.
- Which project, repository or branch (the front door and `prepare`
  infer those and have their own single question).
- Priority, estimate, assignee, due date. Not the factory's business.
- "Is this a bug or a feature?" The ticket type is inferred from cues.
