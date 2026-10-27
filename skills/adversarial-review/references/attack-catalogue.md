# Attack catalogue

Moves a verifier picks from when attacking a claim. Each move names when it
applies (claim `type` and interface kind), how to exercise it from outside
the code, and what "held" and "broke" look like so the attempt line in the
report is a comparison, not an opinion.

Interface kinds: **CLI** (a command with arguments, stdin, exit code),
**HTTP** (requests to a running service), **UI** (a browser or terminal
screen a person drives), **library** (a function exercised through a test
or REPL named in How to run), **batch** (a job that reads inputs, writes
outputs, exits).

Rules for picking:

- Aim at the claim's `expect`. A move that cannot change what `expect`
  describes does not count as an attempt for that claim.
- Use the claim's `hostile inputs` hints as the first attempt, then pick
  moves the hints did not cover.
- Prefer moves from `## Learned` that match the claim type: they found
  bugs in this codebase or this team's work before.
- One move with several inputs is one attempt; two moves is two attempts.

## Fuzzer

### Boundary values
- applies: functional, negative, perf; CLI, HTTP, library, batch
- execute: for each numeric or length-bounded input, send values at and
  just past the stated limits, zero, negative, and very large magnitudes
- held: rejection in the spec's error shape, or the correct result inside
  bounds, with the same exit code or status every time
- broke: crash, stack trace, silent clamp or truncation, wrong result,
  acceptance of an out-of-range value

### Empty and absent
- applies: functional, negative; all kinds
- execute: omit each argument, field or file; supply empty strings, empty
  collections, null, whitespace only, an empty file, a directory where a
  file is expected, closed stdin
- held: a specific rejection naming the missing thing, or the documented
  default
- broke: null in output, a generic 500 or traceback, an undocumented
  default, hanging on stdin

### Oversized input
- applies: functional, perf; all kinds
- execute: inputs far larger than the spec implies: multi-megabyte files,
  very long single strings, lists of many thousands of items, deeply
  nested structures
- held: completes within the spec's stated time, or rejects with a size
  limit the spec names
- broke: out of memory, timeout with no message, partial output written as
  success, quadratic slowdown visible as minutes

### Unicode and encoding
- applies: functional, negative, ux; all kinds
- execute: combining marks, bidirectional text, emoji, look-alike
  characters, embedded control bytes, invalid byte sequences, byte-order
  marks, mixed line endings, names with spaces and quotes, multi-byte
  characters in length-limited fields
- held: round-trips unchanged, lengths counted the way the spec says,
  invalid input rejected with a clear message
- broke: garbled text, truncation mid-character, a length limit that
  counts bytes where it should count characters, a crash on decode

### Malformed structure
- applies: functional, negative; HTTP, CLI, library, batch
- execute: truncated or syntactically invalid payloads, wrong value types,
  duplicate or unknown keys, a missing required field alongside a
  similarly named extra, the wrong content type, trailing junk
- held: rejection that names the field, with no partial processing
- broke: half-applied changes, quiet coercion of the wrong type, a 500
  where a 400 belongs, internal detail in the error

### Repetition and idempotency
- applies: functional, negative; HTTP, CLI, batch
- execute: run the same successful operation twice, many times, in a loop;
  retry after success; interrupt the process mid-run and run again
- held: the repeat is a no-op or a clear "already exists"; state is
  identical after one run and after many
- broke: duplicates, counters that drift, a repeat that fails where the
  first passed, state corrupted by the interrupted run

### Concurrency
- applies: functional, perf; HTTP, CLI, batch
- execute: two writers on the same record at once, a reader during a
  writer, two jobs on the same input, using the shell's background and
  wait
- held: both complete with consistent state, or one is rejected with a
  conflict the spec describes
- broke: lost update, torn file, deadlock, a process seeing a half state,
  results that differ on repeat

### Ordering
- applies: functional, negative; HTTP, UI, batch
- execute: steps out of the documented order, events that arrive late for
  a record already removed, argument orders the CLI claims not to care
  about
- held: a specific rejection for an impossible order, or the same result
  where order should not matter
- broke: success on an impossible sequence, a different result for a
  reordering the spec calls equivalent

### Time and locale
- applies: functional, compat; all kinds
- execute: different time zones, a daylight-saving transition, a leap day,
  extreme years, the epoch, locales with different letter casing or
  decimal separators, a clock set in the future
- held: identical results and formats across settings unless the spec says
  output is localised
- broke: off-by-one-day, parse failures on separators, casing bugs, sort
  order changes, a date that does not round-trip

### Filesystem and paths
- applies: functional, negative; CLI, batch
- execute: relative and absolute paths, parent-directory references,
  symlinks, a read-only destination, a missing parent directory, a path
  with spaces, a very long name, the same path for input and output, an
  output that already exists
- held: a clear error for each impossible case, no partial output left on
  failure
- broke: a write outside the target, a symlink followed somewhere
  surprising, a silent overwrite, a zero-byte file left on error

### Leftover state
- applies: functional; CLI, batch, UI
- execute: run from a directory that already holds previous output,
  interrupt a run and start again, pre-fill the cache or temp area, leave
  a stale lock in place
- held: a clean start or a clear resume story, matching the spec
- broke: stale results served, a refusal with no recovery path, a crash on
  the leftover

## Attacker

The attacker's job is to confirm the access rules and trust boundaries the
spec promises, by trying to step over them from the client side only. Every
attempt is a real request or invocation and a comparison of what came back
against what the spec says a non-privileged caller should get. Report what
the system actually returned, never a theory of what might be wrong.

### Missing or wrong credentials
- applies: security, negative; HTTP, UI
- execute: repeat each `verify` request with no credential, an expired or
  malformed one, and one issued for a different environment or scope
- held: the spec's rejection status with no data and no detail about which
  part was wrong
- broke: data in the body, a success where a rejection belongs, internal
  detail in the error, timing that reveals whether a record exists

### Cross-tenant and object references
- applies: security, negative; HTTP, UI, CLI with accounts
- execute: as one fixture user, reference identifiers belonging to another
  (from fixtures, from sequences, from error messages); change the owning
  account in the path, header and body, together and one at a time
- held: a rejection indistinguishable from a nonexistent identifier, with
  nothing of the other account's data leaking
- broke: another account's record read or changed, an error that confirms
  its identifier exists, a listing that returns more than the caller's own
  rows

### Privilege and ownership fields
- applies: security, negative; HTTP, UI
- execute: attempt a privileged action as an ordinary fixture user; include
  ownership or role fields in a create or update that the spec does not
  list as writable; reuse a privileged caller's entry point as an ordinary
  one
- held: the extra field is ignored or rejected and the privileged state is
  unchanged
- broke: the field took effect, the action succeeded, or the error reveals
  internal field names the spec never promised

### Input that crosses an interpreter
- applies: security, negative, and functional claims on user input; all
  kinds
- execute: in fields and arguments that the spec says are treated as data,
  supply values containing the control syntax of a shell, a query language,
  a template engine, a path, or a response header, to check the value is
  kept as data rather than interpreted. Keep payloads minimal and in
  `scratch`; the goal is to observe handling, not to cause damage, so stop
  at the first sign a value is interpreted and record it
- held: the value is stored and echoed back as inert text, a path resolves
  inside the intended directory, a command treats the value as one argument
- broke: the value is evaluated or executed, a path resolves outside the
  intended directory, the value appears unescaped in a place that changes
  meaning (a response header, rendered markup, a downstream query)

### Rate, quota and resource abuse
- applies: security, perf, negative; HTTP, CLI, batch
- execute: send bursts far above any stated limit, open many sessions at
  once, start an operation whose input never ends, request work sized to
  exhaust memory or disk
- held: throttling, a quota rejection, or bounded resource use the spec
  describes
- broke: unbounded growth, the limit not enforced, one caller degrading the
  service for others

### Error-path disclosure
- applies: security, negative; HTTP, UI, CLI
- execute: drive each failing path on purpose (bad input, a missing
  record, a forced internal error) and read the full response body, the
  headers, and any log line the spec points at
- held: a generic message with no internal paths, versions, secrets or
  other accounts' data; logs free of credentials
- broke: a stack trace, a file path, a configuration value, a token or
  another account's data in the output or the log

### Replay
- applies: security, negative; HTTP
- execute: capture a successful request and resend it unchanged; reuse a
  single-use token, idempotency key or one-time link a second time
- held: the resend is a safe no-op or a clear rejection, matching the spec
- broke: the action repeats, the single-use value works twice, a stale
  value is still accepted

## Stranger

### Follow the runbook literally
- applies: all claims; all kinds
- execute: in a clean shell, run every line of `## How to run` and then
  each `verify` exactly as written, reading nothing but the spec
- held: every step works as described with the tools and versions a
  newcomer would have
- broke: a missing step, an assumed tool or variable, a path that does not
  exist, a term the spec never defined, output that differs from `expect`

### Empty, loading and error states
- applies: ux; UI
- execute: reach the feature with no data, during a slow load, and after a
  forced failure
- held: each state is legible and matches what the spec describes
- broke: a blank screen, a spinner that never resolves, an error with no
  recovery, a layout that collapses

### Keyboard and focus
- applies: ux; UI
- execute: drive the flow with the keyboard alone; tab through controls and
  watch focus order and visible focus
- held: every control is reachable and operable, focus order follows the
  visual order
- broke: a trap, an unreachable control, invisible focus, an action only
  the mouse can perform

### Viewport and zoom
- applies: ux; UI
- execute: a narrow phone width, a very wide screen, and large text or
  browser zoom
- held: content reflows and stays usable
- broke: clipped content, overlap, horizontal scrolling, a control pushed
  off screen

### Slow and interrupted network
- applies: ux; UI, HTTP
- execute: throttle the connection, refresh mid-flow, navigate back during
  an action
- held: progress is shown, partial states recover, no duplicate action on
  resubmit
- broke: a frozen screen, a lost form, a duplicate submission, a wedged
  state

### Message and documentation honesty
- applies: ux, functional; all kinds
- execute: compare each message, help text and documented behaviour against
  what actually happens; read `--help` or the usage text and follow it
- held: messages and docs match behaviour and name the next step
- broke: a misleading error, a silent success where feedback was promised,
  help that describes an option that does not exist or differs from the
  spec

## Learned

The learner appends moves here that found a real bug in this codebase, so
later rounds try them first. Each entry, newest last:

```
- YYYY-MM-DD | <persona> | claim type <type>, interface <kind> | <move in
  one line>: <what it found>
```

Leave this list in place when regenerating the catalogue; it is the only
part the learner writes.
