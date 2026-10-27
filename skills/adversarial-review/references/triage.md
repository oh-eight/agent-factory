# Triage

After the merged report passes lint, `adversarial-review` decides for each
finding whether it goes back into the loop or waits as a follow-up ticket.
This file holds the severity definitions, the defer rule, the follow-up
template, and the ledger schema.

## Severity

Same definitions the report template uses; repeated here so triage is
self-contained.

- `high`: data loss; any security or tenancy break; a stated acceptance
  criterion not met; a crash on plausible input.
- `medium`: a wrong result on edge input; a misleading error; a rejection
  the spec promised that does not happen.
- `low`: cosmetic; wording; a nice-to-have the spec never promised.

Category comes from the verifier:

- `implementation-bug`: the code does the wrong thing against a claim.
- `spec-gap`: the spec is contradictory, vague, or silent where it should
  not be. All `## Spec-level findings` are this category.
- `env`: `## How to run` or `## Entry points` did not let the verifier run
  the system as written.

## The defer rule

A finding is **deferred** to a follow-up ticket when all three hold:

1. `severity` is strictly below `config.triage.defer_below`
   (default `medium`, so only `low` qualifies);
2. `category` is not `security`, and there is no such category, so this
   means: the finding is not a security break; and
3. the claim it is attached to does not have `type: security` in `spec.md`.

Everything else is `triage: loop`:

- every `high` and every `medium` finding, whatever its category;
- every `env` finding, because an environment the verifier cannot run is a
  spec or runbook problem the next round must fix, never a follow-up;
- every spec-level finding (`claim: spec`), because a vague or contradictory
  spec has to be fixed before the claim can be trusted;
- anything a security claim produced, and anything the verifier marked as a
  security break, at any severity.

A round is CLEAN only when no finding is `triage: loop`, no claim is
UNVERIFIABLE, and `## Spec-level findings` is empty. Deferred findings do
not block CLEAN; they ride along as follow-up tickets.

When a finding is deferred:

1. Append its full `### F-` block to `verification/deferred-findings.md`
   under a `## Round N — <date>` heading, so the record outlives the round
   file.
2. Unless `config.offline`, create a follow-up ticket (template below),
   link it, and write `- triage: deferred → <new key>` on the finding.
3. `config.offline` → write `- triage: deferred → (offline)` and note in
   the return that follow-ups were skipped.

A FAIL whose only finding is deferred keeps its `FAIL` verdict line but is
not counted as a loop finding, so it does not by itself block CLEAN. If the
same claim also has a loop finding, the claim blocks CLEAN through that one.

## Follow-up ticket template

Created through `tracker.create` then `tracker.link`, never a vendor tool by
name. Prose goes through `voice.polish(text, durable)` first.

```
summary:     <finding fingerprint as a sentence, e.g.
             "sum CLI: empty argument list prints a blank line">
type:        <the profile's default work-item type, e.g. Bug or Task>
project:     <config.default_project, or the parent ticket's project>
labels:      [factory-followup]
description: |
             Deferred from the adversarial-review loop on KEY (round N).
             Severity: low. Category: <category>.

             Claim: C<n> — <the claim text>
             Expected: <finding.expected>
             Observed: <finding.observed>

             Repro:
             <finding.repro, verbatim>

             Fingerprint: <fingerprint>
link:        relates → KEY
```

After creation, the new key is written onto the finding
(`- triage: deferred → KEY-999`) and named in the ledger entry's `ticket`
field. The origin run's hygiene comment lists every follow-up key it
created that round.

## `ledger.json`

One object, fingerprint → record, at `verification/ledger.json`. It is the
memory the valve reads: a fingerprint whose `rounds` end in two consecutive
numbers with `status: open` is a break that survived a fix, which trips the
valve in `pipeline`.

Schema:

```
{
  "<fingerprint>": {
    "claim":  "C4",                     // claim id, or "spec" for spec-level
    "rounds": [1, 2],                   // rounds this fingerprint appeared, ascending, no repeats
    "status": "open | fixed | deferred",
    "ticket": "KEY-999 | null"          // the follow-up key when deferred, else null
  }
}
```

Update rules each round (step 7 of the skill):

- a fingerprint in this round's merged report: append the round number to
  `rounds`; `status` is `deferred` with its `ticket` when triage deferred
  it, otherwise `open`; set `claim` from the finding.
- a fingerprint already `open` that is **absent** from this round: set
  `status: fixed`. It stays in the file as a record.
- a `deferred` entry is never reopened or marked fixed; the follow-up ticket
  owns it now.
- an INVALID round records its findings as `open` but marks nothing
  `fixed`, because absence in a round that failed lint proves nothing.

Example after a round 2 that fixed one break, saw another return, and
deferred a cosmetic one:

```json
{
  "c4-empty-list-blank-line": { "claim": "C4", "rounds": [1],    "status": "fixed",    "ticket": null },
  "c7-negative-count-crash":  { "claim": "C7", "rounds": [1, 2], "status": "open",     "ticket": null },
  "c2-help-text-typo":        { "claim": "C2", "rounds": [2],    "status": "deferred", "ticket": "ABC-451" }
}
```

Here `c7` appearing in rounds 1 and 2 while still `open` is exactly the
signal the valve trips on.
