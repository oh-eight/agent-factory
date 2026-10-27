# Verification report

One file per persona (`verification/round-N-<persona>.md`) in this exact
shape, then one merged file (`verification/round-N.md`) in the same shape
with the attempts of every persona under each claim. The lint below runs on
the merged file; a report that fails it is INVALID, whatever its verdict
says.

```markdown
# Verification round N — KEY
verdict: CLEAN | FINDINGS | BLOCKED
head: <sha>  base: <sha>  spec_hash: <sha256 of spec.md>
isolation: subagent | same-session
personas: fuzzer, attacker, stranger          # merged file only; single-persona files name one
started: <iso>  finished: <iso>

## Environment
<Exactly how the system was brought up and exercised: commands run from
"How to run", versions seen, fixtures used. Anything that did not work as
written is a finding of category env.>

## Claims
### C1 — PASS
- baseline: <the verify line as run> → <observed>
- attempts (fuzzer):
  1. <what was tried> → <observed> → held
  2. …
  3. …
- attempts (attacker): …
- attempts (stranger): …

### C4 — FAIL → F-N-1
- baseline: … → <observed, differs from expect>

### C7 — UNVERIFIABLE → F-N-2 (env)
- reason: <what in "How to run" or "Entry points" was missing>

## Findings
### F-N-1  fingerprint: <claim-id>-<short-slug>  repeat-of: F-(N-1)-2 | none  personas: fuzzer, stranger
- claim: C4
- category: implementation-bug | spec-gap | env
- severity: high | medium | low
- triage: loop | deferred → <follow-up key>        # filled by the skill, not the verifier
- repro: <exact steps or command a stranger can rerun>
- observed: <what happened>
- expected: <what the spec says>
- note: <one line of interpretation, optional>

## Spec-level findings
<Contradictions between claims, validation statements with no negative
claim, claims that cannot be verified as written. Each becomes a finding
with category spec-gap and claim "spec".>

## Files opened
<Every path read during the run, one per line, including scratch files.>

## Coverage
claims: 12  pass: 11  fail: 1  unverifiable: 0  attempts: 123  deferred: 0
```

## Fingerprints

`<claim id>-<three to five word slug of the failure>`, lower-case, hyphens.
The verifier compares against its own previous reports (given as inputs)
and sets `repeat-of` when the same claim fails the same way. The skill uses
fingerprints for `ledger.json` and the valve.

## Severity

- `high`: data loss, security, a stated acceptance criterion not met, a
  crash on plausible input.
- `medium`: wrong result on edge input, misleading error, missing rejection
  that the spec promised.
- `low`: cosmetic, wording, a nice-to-have the spec did not promise.

## Lint (run by `adversarial-review` on the merged file)

1. `verdict:` line present with one of the three values.
2. Every `### C<n>:` in `spec.md` (except `status: removed-*`) appears as
   `### C<n> — PASS|FAIL|UNVERIFIABLE`.
3. Every PASS has at least `min_attempts` numbered attempts under **each**
   persona in `personas:` (default 3; 1 for `type: ux`).
4. Every FAIL and UNVERIFIABLE has a finding with a `repro:` line (or
   `reason:` for env).
5. `## Files opened` contains no repo-relative path with a source extension
   (`.java .kt .ts .tsx .js .py .go .rs .rb .cs .swift .scala .c .cpp .h`)
   that is not listed under `## Entry points` in the spec. Absolute paths
   (the verifier's own scratch payloads and scripts) are not checked.
6. `verdict: CLEAN` only if fail = 0 **after triage**, unverifiable = 0,
   and `## Spec-level findings` is empty.
7. `## Coverage` counts match the claim sections.

A report that says CLEAN and fails any rule is INVALID. The skill re-prompts
the persona once with the failing rule numbers, then records INVALID.
