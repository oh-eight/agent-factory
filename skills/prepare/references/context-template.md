# context.md

Written whole by `prepare` in round 1 at `$FACTORY_HOME/<KEY>/context.md`.
Rounds after the first append one `## Round N delta` section each and
change nothing above it. The spec-writer, intent-verifier, builder and
decomposer read this file; verifiers never do.

Rules for filling it:

- Acceptance criteria are copied verbatim from the ticket and numbered
  `AC-1`, `AC-2`, ... in the order they appear. Never paraphrase them.
- Every item under `## Sources`, `## Codebase` and `## Related` ends with
  one relevance line: what in it matters for the acceptance criteria.
  Items without relevance are dropped, not listed.
- Paths in `## Codebase` are relative to the repository root. Commands are
  copied from the map, not retyped.
- Leave `## Operational context` out when step 6 of the skill gathered
  nothing for it. Never write an empty section with placeholder text.
- `## Open questions` lists what the ticket does not decide and what the
  fetches could not reach. The spec-writer turns each into a non-goal, a
  claim, or an item for the critic.

## Shape

```markdown
# Context: <KEY> — <ticket summary>
key: <KEY>   round: 1   repo: <owner/repo>   branch: <branch name>   size: <S|M|L|XL or pending>
written: <iso time>   profile: <profile name>

## Ticket
- url: <ticket url>
- type: <issue type>   component: <component or none>   labels: <labels or none>
- parent: <parent key and summary, or none>
- summary: <verbatim>

### Description
<verbatim, trimmed only of boilerplate the tracker adds; keep links inline>

### Acceptance criteria
- AC-1: <verbatim>
- AC-2: <verbatim>

### From the comments
- <date> <author>: <the decision, constraint or correction, one line each>

## Sources
- `sources/01-<slug>.md` <kind> <title or url>. Relevance: <one line>
- `sources/02-<slug>.md` ...

## Codebase
From `$FACTORY_HOME/_repos/<owner>-<repo>.md` area `<area>` (mapped <date>).

- where this lives:
  - <path>: <what it is and which AC it serves>
- entry points:
  - <path>: <what starts here>
- nearest existing pattern: <path and one line on why to copy it>
- how to run:
  - setup: <command>
  - start: <command>
  - tests: <area test command>   single test: <pattern>
  - fixtures: <helpers, env vars, accounts>
- flags: <mechanism and the declaration file, or none>
- conventions that apply here:
  - <one line each>
- gotchas:
  - <one line each>

## Related
- PRs:
  - <#n or url> <title>. Relevance: <one line>
- sibling tickets:
  - <KEY> <summary> (<status>). Relevance: <one line>
- docs:
  - <title or url>. Relevance: <one line>
- queries run: <one line per family listing the query strings, so later rounds do not repeat them>

## Operational context
<!-- only when the ticket wording triggered incidents or obs lookups -->
- incidents:
  - <id> <title> (<date>). Relevance: <one line>
- alerts firing: <list or none>
- baseline:
  - <metric or log query>: <value over the window>. Relevance: <one line>

## Open questions
- <what the ticket does not decide>
- <URL or capability that could not be fetched, and what it was expected to contain>
```

## Round delta

Appended by `prepare` for every round after the first:

```markdown
## Round N delta
read: verification/round-(N-1).md, nurse/ci-findings.md, nurse/review-findings.md, sanity.md, instructions[]

| Finding | Category | Route | What changed |
|---|---|---|---|
| F-(N-1)-1 | implementation-bug | builder, claim C4 unchanged | repro copied below; entry point `<path>` |
| F-(N-1)-2 | spec-gap | spec-writer: new claim | proposed claim text below |
| F-(N-1)-3 | env | fix How to run | `tests:` command corrected in the map and in `## Codebase` |
| CI-1 | implementation-bug | builder | failing job and the assertion that broke |
| R-1 | spec-gap | spec-writer: changed claim C7 | reviewer asked for a different error message |
| I-1 | spec-gap | spec-writer: new claim | answer from the escalation instruction |
| F-(N-1)-4 | implementation-bug (repeat) | builder | same fingerprint as round N-2; noted for the valve |

### Repros
- F-(N-1)-1: <verbatim repro, observed, expected>

### Proposed claim changes
- F-(N-1)-2: <what the new or changed claim should state and expect>

### How to run corrections
- <the command that failed, the corrected command, where it was fixed>

### New context this round
- <source, PR, ticket or doc found in the targeted pass>. Relevance: <one line>
```

Finding ids keep the id from the file they came from: `F-N-k` from the
verification report, `CI-k` from `nurse/ci-findings.md`, `R-k` from
`nurse/review-findings.md`, `S-k` from `sanity.md`, `I-k` for an
instruction. Categories are exactly `env`, `spec-gap`,
`implementation-bug`; a repeated fingerprint keeps its category with
`(repeat)` after it.
