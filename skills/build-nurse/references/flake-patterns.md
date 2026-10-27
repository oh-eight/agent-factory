# Flake patterns (generic)

Read by `build-nurse` step 5. The profile may point at a vendor file through
`ci.flake_patterns`; that file has the same three sections and is consulted
after **Never retry** and before the generic table here. The learner appends
to `## Learned` only; nothing else in this file is edited at run time.

## Matching

Match the job's evidence (structured root cause when present, else the
last 200 log lines) in this order: Never retry → profile file → Learned →
Generic. First hit wins. Patterns are case-insensitive regexes unless they
read as a phrase; a phrase matches as a substring.

Classification and action:

| Class | Meaning | Action |
|---|---|---|
| `flake` | the job would likely pass if run again, unchanged | `ci.retry` while `retries[job] < 2`, then treat as `infra` |
| `infra` | the failure is in the CI system, not the code, and a retry will not help | no retry; `nurse.blocked`, one DM |
| `real` | the code or configuration under test failed | diagnose and attribute (SKILL.md step 7) |

## Never retry

Any of these present anywhere in the evidence makes the job `real`, even if
a flake pattern also matches further down the log:

| Pattern | Why |
|---|---|
| `error: .*(cannot find symbol|undefined reference|does not exist|no such module|is not defined|has no attribute)` or `compilation failed`, `error TS\d+`, `SyntaxError`, `cannot compile` | compile error |
| `AssertionError`, `assert(ion)? failed`, `expected .* (but was|to (equal|be|contain))`, `Expected:.*Actual:`, `FAIL: Test`, `--- FAIL:`, `\d+ failed, \d+ passed`, `Tests failed: \d+` | assertion failure |
| `lint`, `eslint`, `checkstyle`, `rubocop`, `golangci`, `clippy`, `prettier --check`, `format check failed`, `buildifier` with a non-zero exit and file paths listed | lint or format failure |
| the failing test name or path is among `pr.files` | the test this PR touched failed |
| `exit status [1-9]\d?` from a test runner with `Tests run:` or `Test Suites:` lines present | the suite ran and something failed |

## Generic

| Pattern | Class | Action |
|---|---|---|
| `agent (lost|disconnected|stopped responding)`, `lost connection to (the )?agent`, `runner.*(offline|lost communication)`, `The operation was canceled` with no test output | `flake` | retry |
| `(fatal|error): (unable to access|could not read from remote|early EOF|the remote end hung up)`, `checkout.*timed out`, `git clone.*(timed out|failed)`, `RPC failed; curl` | `flake` | retry |
| `(ETIMEDOUT|ECONNRESET|EAI_AGAIN|ENOTFOUND)`, `Could not resolve host`, `Temporary failure in name resolution`, `getaddrinfo` | `flake` | retry |
| `(fetch|download|resolve).*(timed out|timeout|failed after \d+ attempts)` naming a registry, mirror, artifact or dependency; `npm ERR! network`, `Could not transfer artifact`, `Read timed out` from a package manager, `Failed to fetch .* from cache` | `flake` | retry |
| `(toomanyrequests|rate limit|429 Too Many Requests)`, `pull access denied` with a retry hint, `docker: Error response from daemon.*(timeout|EOF|TLS handshake)`, `image pull.*(back-off|timeout)` | `flake` | retry |
| `exit status -1`, `exit code 137`, `exit code 143`, `Killed`, `signal: killed` with **no** test or compile failure above it | `flake` | retry |
| `OOMKilled`, `out of memory`, `Cannot allocate memory`, `java.lang.OutOfMemoryError` inside a setup, fetch, cache or build-tool step (not inside the test run) | `flake` | retry once; second time `infra` |
| `@Flaky`, `@flaky`, `@RetryingTest`, `FlakyTest`, `retries: \d`, `marked flaky`, `known flaky` next to the failing test name | `flake` | retry |
| `(timed out|timeout|deadline exceeded) after \d+` or `exceeded the timeout of` with no assertion, compile or lint failure anywhere | `flake` | retry |
| `No space left on device`, `disk quota exceeded` | `infra` | block |
| `(401|403).*(registry|credential|unauthori[sz]ed|permission denied)` from a CI step, `secret .* not found`, `AccessDenied` on a CI bucket or cache | `infra` | block |
| `no agents? available`, `waiting for an agent`, `queue.*(full|stuck)`, job in `pending|scheduled` for over 2 h with no log | `infra` | block |
| `(502|503|504) (Bad Gateway|Service Unavailable|Gateway Time-out)` from the CI system or its artifact store, `internal server error` from the CI API | `infra` | block |
| `cache (restore|save) failed`, `corrupt(ed)? (cache|archive)`, `unexpected end of (file|archive)` on a cache step | `flake` | retry; second time `infra` |

Notes for classifiers:

- "No test failure above it" means: scan the whole evidence for any Never
  retry pattern before applying a `flake` row. Timeouts and kills that come
  after a failing assertion are `real`.
- A job that fails the same way on its second retry stops being a flake.
  SKILL.md moves it to the real/infra path with `retries exhausted`.
- A `flake` that keeps recurring across runs is a lesson. The learner reads
  `nurse/log.md` across runs and appends to `## Learned`; a count above 5
  for the same pattern and job is worth a follow-up ticket, not more
  retries.

## Learned

Appended by `learner`, one line per entry, newest last. Format:

```
- <date> | <pattern as regex or phrase> | <class> | <job or scope> | count=<n> | <KEY where seen>
```

Entries here outrank the Generic table but never the Never retry list.
