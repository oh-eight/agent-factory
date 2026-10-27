# Comment classes

Every new review thread gets exactly one class. When two fit, take the one
lower in this table (a nit that changes behaviour is `behaviour`; a question
that argues against the spec is `disagree`). Read the comment, the hunk it
points at, and the spec claim that covers that code before deciding.

| Class | Cues in the comment | Examples |
|---|---|---|
| `question` | "why", "how does", "what happens when", "is this", "did you consider"; no imperative; no proposed change | "Why a 30 s timeout here?"; "Does this handle an empty list?"; "Where is this called from?" |
| `nit` | "nit:", "tiny", "optional", "prefer", "could be", a rename, reorder, dead code, import, formatting, test name, constant extraction | "nit: `maxRetries` → `MAX_RETRIES`"; "unused import"; "could inline this helper"; "prefer `isEmpty()` over `size() == 0`" |
| `wording` | points at text a person reads: PR title, PR body, a code comment, docstring, README line, log line, error message; "typo", "reads oddly", "the description says" | "typo: recieve"; "the body still says draft"; "this error message should mention the key" |
| `behaviour` | asks for a different observable result, a missing case, a bug report, a security or data concern, a new validation, a changed default; or any `nit` that fails the small test | "this will NPE when the user has no team"; "we should reject negative amounts"; "needs a flag"; "this changes the sort order for everyone" |
| `disagree` | asks for something the spec's `## Scope`, `## Non-goals`, a claim, or the ticket explicitly rules out or decides the other way | "just make it async" when the ticket says synchronous; "drop the validation, callers already check" when a `negative` claim requires it |

Not a class, no reply, not counted: approvals with no text, "LGTM", emoji
only, bot comments, and comments the factory wrote.

## Reply templates

Plain, short, in the `chat` register of `voice.polish`. Start with the
answer or the action. No greeting, no thanks, no sign-off, no emoji. The
profile's `comment_prefix` is prepended after polishing.

```
question
  <answer in one or two sentences>. Spec C<n>: "<quoted expect line>".
  <optional: link to the ticket line or context.md source>

question, not answerable from the files
  <what the files do say>. The rest needs <author or team>; leaving this open.

nit / wording in the diff
  Done in <short sha>: <what changed in one clause>.

wording in the PR body or title
  Updated the <Problem|Solution|Testing|Context|title>: <one clause on what it now says>.

behaviour
  Agreed, this is a <bug|gap>. Filed as F-<round+1>-R<k>; round <round+1> picks it up and this thread gets the sha.

behaviour, downgraded from a nit
  This is more than a small change (<reason: lines|behaviour|dependency>), so it goes through the loop as F-<round+1>-R<k>.

disagree
  The ticket asks for <quote or paraphrase> (<link or spec claim C<n>>), so the change stays as is. If that should change, the ticket is the place to decide it; leaving this open for you.
```

Never reply twice to the same comment. Before posting, check the thread for
a factory reply newer than the comment; if one exists, skip.

## What counts as "small"

A `nit` or `wording` change is applied directly only when all of these hold:

| Rule | Limit |
|---|---|
| Size | 20 changed lines or fewer (`git diff --numstat` additions plus deletions) across the whole fix |
| Behaviour | No change to any observable result: no new branch, no changed default, no changed validation, no changed output format or message semantics (fixing a typo in a message is fine; changing what it says about the error is `behaviour`) |
| Dependencies | No new import from outside the repository, no manifest or lockfile change |
| Surface | Only files already in the PR diff, plus their tests |
| Tests | The quick test command from cartography still passes, when it runs in a few minutes; if it cannot be run, say so in the reply |
| Spec | No claim in `spec.md` changes status or text |

Anything that fails one rule is classed `behaviour` and goes to
`nurse/review-findings.md`. The reply says which rule it failed.

## What never happens

- Resolving a thread. The reviewer decides when they are satisfied.
- Approving the PR, requesting changes, or dismissing a review.
- Force-pushing, rebasing, amending, or squashing on the branch during a
  nurse pass. New commits only.
- Editing or deleting anyone else's comment.
- Replying without the profile's `comment_prefix`.
- Implementing a `disagree` request. The spec or ticket changes first,
  through a human, then the loop picks it up as an instruction.
- Starting the new prepare round inside the pass. The nurse sets the
  stage and round; `pipeline KEY` runs it.
- Merging.

## Finding shape for `nurse/review-findings.md`

Same shape as a verification finding
(`adversarial-review/references/report-template.md`), so the next round's
`prepare` classifies it like any other:

- `fingerprint: review-<thread id>-<three to five word slug>`
- `category: implementation-bug` when a built claim is wrong;
  `spec-gap` when no claim covers what the reviewer describes.
- `severity: high` for data, security, or a stated acceptance criterion;
  `medium` otherwise. Reviewer comments are never `low` (a low would have
  been a nit).
- `repro:` made concrete from the comment (input, call, UI steps), not a
  paraphrase of the comment.
- `source:` the comment url, so the round can reply with the fix sha.
