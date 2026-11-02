# Spec: TOY-1 — Sum command
round: 1   base: main@0000000   repo: toy/sum   branch: toy-1   size: S

## Scope
`bin/tool` prints the sum of its integer arguments.

## Non-goals
- Floating point input.

## How to run
- start: `make && bin/tool 2 3`

## Entry points
- `bin/tool.c`: the command, run it.

## Claims
### C1: Adds its arguments
- type: functional
- verify: `bin/tool 2 3`
- expect: `5`
- source: AC-1
- status: open

### C2: Usage text is readable
- type: ux
- verify: `bin/tool` with no arguments
- expect: one usage line on stderr
- source: AC-2
- status: open

### C3: Reads from stdin
- type: functional
- verify: `echo 2 3 | bin/tool -`
- expect: `5`
- source: AC-3
- status: removed-r1

### C4: Rejects non-numeric input
- type: functional
- verify: `bin/tool a; echo "exit=$?"`
- expect: an error on stderr, then `exit=1`
- source: AC-4
- status: open

### C5: Prints a newline
- type: functional
- verify: `bin/tool 1 | od -c`
- expect: ends in `\n`
- source: AC-5
- status: open
