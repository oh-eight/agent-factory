# Verification report

One file per persona (`verification/round-N-<persona>.md`) in this exact
shape, then one merged file (`verification/round-N.md`) in the same shape
with the attempts of every persona under each claim. The lint below runs on
the merged file; a report that fails it is INVALID, whatever its verdict
says. Personas write only `CLEAN`, `FINDINGS` or `BLOCKED`; `SHIP` is
written by the skill after triage, in the merged file only.

```markdown
# Verification round N — KEY
verdict: CLEAN | SHIP | FINDINGS | BLOCKED
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
- category: implementation-bug | spec-gap | env | security
- severity: high | medium | low
- triage: loop | known → <follow-up key> | deferred → <follow-up key>   # filled by the skill, not the verifier
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

## Category

- `implementation-bug`: the code does the wrong thing against a claim.
- `spec-gap`: the spec is contradictory, vague, or silent where it should
  not be; every spec-level finding.
- `env`: `## How to run` or `## Entry points` did not let the verifier run
  the system as written.
- `security`: a security break, whatever the claim: injection or other
  input that crosses an interpreter, escaping a trust boundary, a leaked
  secret, an auth, privilege or tenancy bypass, a rate, quota or resource
  limit not enforced, internal detail on an error path (a stack trace, a
  file path, a configuration value, a token, another account's data), a
  replay or a single-use value that works twice. Every `broke:` in the
  Attacker section of `attack-catalogue.md` is one. It blocks the round at
  any severity.

## Lint (run by `adversarial-review` on the merged file)

1. Exactly one `verdict:` line, with one of `CLEAN`, `SHIP`, `FINDINGS`,
   `BLOCKED`.
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
6. Triage words and `verdict:` match what the findings' own fields say.
   Every `### F-` block under `## Findings` and `## Spec-level findings`
   is classified, the blocking test first. A finding **blocks** when its
   severity is `high` (spec-level included), or its category is
   `security` (any severity), or it sits on a `type: security` claim at
   `medium` or worse. An unrecognised severity or category (anything but
   `low`/`medium`/`high` and the four categories above, `Medium` and
   `Security` included), a missing one, a `- claim:` that is neither
   `spec` nor a claim id in `spec.md`, or one of those lines given twice,
   also blocks (fail closed). A `deferred` line never hides a blocking
   finding. A non-blocking finding under `## Findings` whose triage is
   `deferred` and whose claim is not `type: security` is skipped. Every
   other finding is a known issue. The wanted triage word is `loop` for a
   blocking finding and `known` for a known issue; each finding whose
   first triage word differs prints `R6 triage <id> want <w> have <h>`
   (`have none` when it has no triage line), in file order. Then the
   verdict, in this order: BLOCKED when there is at least one claim
   section and every one is UNVERIFIABLE; else FINDINGS when a finding
   blocks or a claim is UNVERIFIABLE; else SHIP when at least one finding
   is a known issue; else CLEAN. A mismatch prints `R6 want <V> have <W>`,
   after the `R6 triage` lines.
7. `## Coverage` counts match the claim sections.

A report that fails rule 2, 3, 4 or 5 goes back to the persona at fault
once, with the failing rule numbers; if it still fails, the skill records
INVALID. Rules 1, 6 and 7 check what the skill itself wrote: it rewrites the
header verdict (rule 1) or writes the script's want values (rules 6 and 7:
the triage word of each `R6 triage` line, the `R6 want` verdict, the `R7
want` Coverage line), lints again, and records INVALID if a line is still
printed. No persona is re-prompted for them.

The executable form of this list is `scripts/lint-report.sh` in this
skill: its default mode checks rules 1–5 and 7 (step 5), and
`--after-triage` checks all seven (step 6). The two must agree.
