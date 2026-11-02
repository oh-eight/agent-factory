# Verification round 1 — TOY-1
verdict: FINDINGS
head: 1111111  base: 0000000  spec_hash: 2222222
isolation: subagent
personas: fuzzer, attacker, stranger
started: 2026-11-02T10:00:00Z  finished: 2026-11-02T10:40:00Z

## Environment
### fuzzer
- `make` then `bin/tool 2 3` as How to run says.
### attacker
- the same.
### stranger
- the same.

## Claims
### C1 — PASS
- baseline: `bin/tool 2 3` → `5`
- attempts (fuzzer):
  1. `bin/tool 0 0` → `0` → held
  2. `bin/tool -4 4` → `0` → held
  3. `bin/tool 2147483647 1` → `2147483648` → held
- attempts (attacker):
  1. `bin/tool '2;id' 3` → error → held
  2. `bin/tool $(printf '%01000d' 1)` → error → held
  3. `bin/tool 1 2 3 4 5` → `15` → held
- attempts (stranger):
  1. `bin/tool 10 20` → `30` → held
  2. `bin/tool 7` → `7` → held
  3. `bin/tool 1 1` → `2` → held

### C2 — PASS
- baseline: `bin/tool` → `usage: tool N...` on stderr
- attempts (fuzzer):
  1. `bin/tool ''` → usage line → held
- attempts (attacker):
  1. `bin/tool --help` → usage line → held
- attempts (stranger):
  1. read the usage line → clear → held

### C4 — FAIL
- baseline: `bin/tool a; echo "exit=$?"` → `0`, `exit=0`

## Findings
### F-1-1  fingerprint: c4-accepts-letters  repeat-of: none  personas: fuzzer, stranger
- claim: C4
- category: implementation-bug
- severity: high
- repro: `bin/tool a; echo "exit=$?"`
- observed: prints `0` and `exit=0`
- expected: an error on stderr and `exit=1`

## Spec-level findings

## Files opened
bin/tool.c
/tmp/scratch/probe.c

## Coverage
claims: 3  pass: 2  fail: 1  unverifiable: 0  attempts: 12  deferred: 0
