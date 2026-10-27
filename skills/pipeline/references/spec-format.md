# Spec format

`spec.md` is the contract between the builder and the verifiers. The
verifiers read **only** this file plus the files it lists under
`## Entry points`, so anything they need to run and judge the system must be
here. Anything about how the code is shaped goes to `spec-impl-notes.md`.

```markdown
# Spec: KEY — <title>
round: N   base: <base branch>@<sha>   repo: owner/repo   branch: <name>   size: S|M|L|XL

## Scope
<What this change makes true, in three to six lines.>

## Non-goals
<What a reader might expect that this change deliberately does not do.>

## Flags and rollback
<Which behaviour is behind a flag, the flag's name and default, and how to
turn the change off in production. "None" is a valid answer with a reason.>

## How to run
- setup: <commands to install, build, seed>
- start: <command, URL or CLI invocation that brings the system up>
- tests: <the test command QA added and the pre-existing suite command>
- fixtures: <accounts, sample files, flags, environment variables>

## Entry points
<Files the verifier MAY open because running the system needs them:
binaries, scripts, config, fixture files. Never source files.>

## Claims
### C1: <one observable behaviour, present tense>
- type: functional | negative | security | ux | perf | compat
- verify: <exact command, request, or UI steps a stranger can run>
- expect: <exact observable result: exit code, response shape, screen state>
- hostile inputs: <optional hints the verifier should extend, never a complete list>
- source: AC-2 | intent-check IC-3 | critique SC-1 | finding F-1-3
- status: open | built | pass-rN | fail-rN

### C2: …

## Changelog
- r1: created, 9 claims
- r2: C4 reworded (F-1-1), C10 added (F-1-3), C6 unchanged
```

## Validity rules

A claim is valid only if someone with repository access and the
`## How to run` section can execute `verify` and compare the outcome with
`expect` **without opening a source file**. The spec-writer checks every
claim against this sentence before finishing.

- Every acceptance criterion in `intake.md` yields at least one claim.
- Every intent check in `intent-checks.md` yields at least one claim or an
  explicit line in `## Non-goals`.
- Every statement of validation, permission or limit yields a `negative`
  claim that shows the rejection.
- Every place where input crosses a trust boundary yields a `security` claim.
- Every finding from a previous round maps to a claim id in `source:` so the
  verifier re-checks it.
- `verify` lines reference nothing outside `## How to run` and
  `## Entry points`.
- Claim ids are stable across rounds. Removed claims stay in the file with
  `status: removed-rN` and a changelog line.

## Lint

`spec-task` checks mechanically before the builder starts:

```bash
grep -c '^### C[0-9]*:' spec.md                       # at least one claim
awk '/^### C[0-9]*:|^## Changelog/{ if (c && !(v&&e&&t)) print "INCOMPLETE " c; c=$0; v=e=t=0 } /^- verify:/{v=1} /^- expect:/{e=1} /^- type:/{t=1} END{ if (c && c !~ /^## Changelog/ && !(v&&e&&t)) print "INCOMPLETE " c }' spec.md
grep -o '^### C[0-9]*' spec.md | sort | uniq -d        # duplicate ids
grep -q '^## How to run' spec.md || echo "NO HOW TO RUN"
grep '^- verify:' spec.md | grep -E '\.(java|kt|ts|tsx|js|py|go|rs|rb|cs|swift|scala)\b'   # source paths in verify
```

Any output from the last line is checked against `## Entry points`; a path
not listed there fails the lint.
