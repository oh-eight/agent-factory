# Triage

After the merged report passes lint, `adversarial-review` decides for each
finding whether it goes back into the loop (`loop`), ships with the change
as a known issue (`known`), or waits as a follow-up ticket (`deferred`).
This file holds the severity definitions, the blocking rule, the defer
rule, the follow-up templates, and the ledger schema.

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
- `security`: a security break (injection or other input that crosses an
  interpreter, escaping a trust boundary, a leaked secret, an auth,
  privilege or tenancy bypass, a rate, quota or resource limit not
  enforced, internal detail on an error path, a replay or a single-use
  value that works twice: every `broke:` in the Attacker section of
  `attack-catalogue.md`). A `security` finding always
  loops: it is never deferred and never a known issue, and it keeps the
  severity the verifier gave it.

## The blocking rule

Checked first, for every finding under `## Findings` and
`## Spec-level findings`. A finding **blocks** (`triage: loop`) when any of
these holds:

- its severity is `high`, whatever its category, spec-level included;
- its category is `security`, at any severity;
- its claim has `type: security` in `spec.md` and its severity is
  `medium` or worse.

A severity or category outside the lists above (`Medium`, `Security`, an
empty or missing line) and a `- claim:` that names no claim in `spec.md`
and is not `spec` also block: fail closed. The blocking test comes before
the defer rule, so a blocking finding is never deferred.

## The defer rule

A non-blocking finding under `## Findings` is **deferred** to its own
follow-up ticket when both hold:

1. `severity` is strictly below `config.triage.defer_below`
   (default `medium`, so only `low` qualifies); and
2. the claim it is attached to does not have `type: security` in `spec.md`.

## Known issues

Every other non-blocking finding is a **known issue**
(`- triage: known → <key>`): it ships with the change and is listed in the
PR body under `### Known issues`. That covers:

- `medium` findings on claims not typed `security`, whatever the category
  (`implementation-bug`, `spec-gap`, `env`);
- spec-level findings (`claim: spec`) at `low` and `medium`; they are never
  deferred and no longer loop;
- `low` findings on a `type: security` claim whose category is not
  `security`; they are never deferred.

`env` and spec-level findings no longer loop by category. An env problem
that stopped a verifier still leaves its claim UNVERIFIABLE, which keeps
the round out of SHIP.

## Verdict

- **CLEAN**: no claim is UNVERIFIABLE and no finding is open; every
  finding, if any, is deferred.
- **SHIP**: no claim is UNVERIFIABLE, no finding blocks, and at least one
  finding is a known issue. The pipeline opens the PR.
- **FINDINGS**: a finding blocks or a claim is UNVERIFIABLE.
- **BLOCKED**: every claim is UNVERIFIABLE.

Deferred findings block neither CLEAN nor SHIP; they ride along as
follow-up tickets.

When a finding is deferred:

1. Append its full `### F-` block to `verification/deferred-findings.md`
   under a `## Round N — <date>` heading, so the record outlives the round
   file.
2. Unless `config.offline`, create a follow-up ticket (template below),
   link it, and write `- triage: deferred → <new key>` on the finding.
3. `config.offline` → write `- triage: deferred → (offline)` and note in
   the return that follow-ups were skipped.

When a finding is a known issue:

1. The run has one combined follow-up issue for all its known issues, the
   shape of the template below. The first round with a known issue creates
   it through `tracker.create` (then `tracker.link`); a later round adds a
   `## Round N` section to the same key with `tracker.comment`. Find the
   key from any ledger entry with `status: known`.
2. Write `- triage: known → <that key>` on the finding.
3. `config.offline` → write `- triage: known → (offline)`.

A FAIL whose only finding is deferred or known keeps its `FAIL` verdict
line but does not block. If the same claim also has a blocking finding,
the claim blocks through that one.

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

## Known-issue follow-up template

One issue per run, created by the first round that has a known issue;
later rounds add their own `## Round N` section as a comment on it. Same
capabilities and `voice.polish` as above.

```
summary:     Follow-ups from KEY verification
type:        <the profile's default work-item type, e.g. Task>
project:     <config.default_project, or the parent ticket's project>
labels:      [factory-followup]
description: |
             Known issues the change for KEY shipped with. Each one passed
             the blocking rule (not high, not security, not medium on a
             security claim) and is listed in the PR's ### Known issues.

             ## Round N
             ### <fingerprint> (<F-id>, <severity>, <category>, <claim>)
             Expected: <finding.expected>
             Observed: <finding.observed>
             Repro:
             <finding.repro, verbatim>
link:        relates → KEY
```

Every known issue of every round names this key in its triage line and in
its ledger entry's `ticket` field.

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
    "status": "open | fixed | deferred | known",
    "ticket": "KEY-999 | null"          // the follow-up key when deferred or known, else null
  }
}
```

Update rules each round (step 7 of the skill):

- a fingerprint in this round's merged report: append the round number to
  `rounds`; `status` is `deferred` or `known` with its `ticket` when triage
  deferred it or made it a known issue, otherwise `open`; set `claim` from
  the finding.
- a fingerprint already `open` that is **absent** from this round: set
  `status: fixed`. It stays in the file as a record.
- a `deferred` or `known` entry is never reopened or marked fixed; the
  follow-up ticket owns it now. The valve's repeat condition reads only
  `open` entries, so neither trips it.
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
