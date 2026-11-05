# PR body (engine default)

Used when the profile's `pr.body` is `builtin:pr-template`. A vendor profile
may point at its own skill instead.

## Title

Imperative, finishes the sentence "This change will …". Prefix the tracker
key in square brackets when there is one: `[ABC-123] Reject non-numeric
arguments in sum`. No trailing period, no conventional-commit prefix.

## Body

```markdown
### Problem

<Who is affected, what goes wrong or is missing, why now. Two to four
sentences from intake.md. Link the evidence.>

### Solution

<What the change does about it and why this shape, from
build/round-N/summary.md. Bullets only for independent parts. Name anything
risky, flag-gated, or deliberately left out.>

### Testing

<Tests added (from qa.md), mutation survivors killed (mutation.md), burn-in
result, and one line: "Adversarial verification round N: X claims, Y
attempts across fuzzer, attacker and stranger, all passed." for a CLEAN
round, or "…, Z known issues, listed below." for a SHIP round. No file
lists.>

### Known issues

<Open issues this change ships with, tracked on the follow-up; they are not
part of the change. One line per finding with `triage: known` in the last
merged verification report (verification/round-N.md):>

- <fingerprint> (<F-id>, <severity>, <claim>) → <follow-up key>

### Context

<Tracker key as a link, the brief's sources, related PRs. Or: No ticket.>

## Stack                       <!-- only when train.json exists -->

1. #123
2. #124 👈 THIS PR
3. #125
```

## Rules

- Never narrate the diff file by file; the reviewer has the diff.
- Never add an AI attribution line.
- Delete a section you cannot fill with facts. Leave `### Known issues`
  out when the last merged report has no `triage: known` finding; when it
  has any, list every one of them, each with the follow-up key from its
  triage line.
- Updating an existing body: read it first, change only sections whose
  facts changed, keep the author's edits, never append a changelog.
- Run `voice.polish(durable)` over title and body before publishing.
