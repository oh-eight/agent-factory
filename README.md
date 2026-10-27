# agent-factory

An autonomous development engine made of markdown skills for Claude Code,
Cursor and Codex, plus the front door that drives it:

```
/intake-oss <anything>
```

`<anything>` is a sentence, a tracker key or URL, a chat permalink, a doc
link, a PR, a CI build, or several of those on one line. The front door
works out what it is, writes or loads the tickets, and runs each through a
build-and-break loop that ends when adversarial verifiers find nothing. It
then opens the PR, keeps it green through CI and review, merges when you say
so, watches the deploy, and writes down what it learned. Called with nothing
it prints the dashboard and resumes what is waiting.

The engine never names a vendor tool. It asks for capabilities (`tracker`,
`pr`, `ci`, `chat`, `obs`, …) and a profile maps each to whatever this
machine has. `/intake-oss` writes that profile by discovery on first run.

## Install

```bash
git clone <this repo> ~/projects/agent-factory
cd ~/projects/agent-factory
./install.sh            # symlinks skills/* into every harness found
./install.sh --check    # what is linked where
./install.sh --uninstall
```

Targets: `~/.claude/skills`, `~/.cursor/skills`, `~/.agents/skills`. Pass
`--target claude|cursor|codex|all` to choose. A target directory that
another tool manages (it is itself a symlink, or holds symlinks into a path
matching one of the colon-separated substrings in `FACTORY_FOREIGN_MARKERS`)
is skipped with a message. A real directory that collides with a skill name
is moved to `<name>.pre-factory`.

Requirements: `git`, `rg`, and whatever your tools are (the engine finds
them). A GitHub or GitLab CLI that is logged in gets you PRs and CI; without
one the run stops before the PR stage and says so.

## First run and discovery

```
/intake-oss
```

With no `$FACTORY_HOME/config.json`, the front door runs discovery:

1. MCP tools visible in the session, plus `claude mcp list` when present,
   matched against tool families (trackers, chat, docs, CI, observability,
   deploy, incidents, code search, dispatch).
2. CLIs on `PATH` with read-only auth probes.
3. Repository signals when run inside a checkout: CI configuration, remote
   host, manifests.

Then it asks one question that bundles only the gaps that change behaviour:
which tracker when two are authenticated or none is (the repository's issue
tracker or the file tracker), chat notifications yes or no, unattended merge
yes or no. It writes `config.json` and `profile.md`, prints one line per
capability and the gaps, and continues with whatever you typed.

`/intake-oss config rediscover` reruns it. `/intake-oss config ignore <name>`
drops a tool family or MCP server and reruns it.

## Grammar

| You type | What happens |
|---|---|
| `/intake-oss` | dashboard, then resume what is resumable |
| `/intake-oss <input…>` | classify, print the reading, create or load tickets, run |
| `/intake-oss <KEY> go` | pass the pending gate |
| `/intake-oss <KEY> stop` | park the run |
| `/intake-oss <KEY> <instruction>` | leave an instruction the next stage reads, then resume |
| `/intake-oss tick` | one heartbeat pass |
| `/intake-oss config [<text>]` | show config, or edit one key from a sentence |

| `/intake-oss refine <input…>` | interview you about the brief or ticket before anything runs |
| `/intake-oss <KEY> refine` | the same on a run that already exists |

Before any write the front door prints a three-line reading (what it saw,
the intent it chose, the next action). If that is wrong, say so; nothing has
happened yet.

A thin brief ("make uploads faster", an empty ticket) is caught before the
first agent spends a round on it: `ticket-refiner` scores the text for a
missing outcome, acceptance criteria, scope or an unmade decision, and asks
up to five questions, each with concrete options and the best guess first.
The answers become the ticket. `refine.mode` in the config turns this to
`always` or `off`; unattended runs never interview and fall back to best
guesses listed as assumptions.

## What the factory does

A ticket goes through `prepare` (repository map, context, sizing and
splitting), `spec-task` (a verifier-safe spec written, checked by an
independent intent verifier and a critic, then built, tested, security- and
UX-reviewed, mutation-audited and burned in), `adversarial-review` (three
personas attack the running system from the spec alone: a fuzzer, an
attacker and a stranger), back to `prepare` while they find anything, then
`pr`, the nurses (`build-nurse` for CI, `review-nurse` for comments,
`pr-sanity-check` once), `merge` behind a gate, `deploy-sentinel` for a
watch window, and `learner`, which writes a lesson and tunes the config.
Epics go through `epic-intake`, which plans or enriches children and hands
the ready set to `factory`. One heartbeat (`tick`) every 15 minutes runs
whatever is due for every active run.

```
input ─► classify ─► ticket(s) ─► prepare ─► spec-task ─► adversarial-review ─┐
                                      ▲                                         │
                                      └──────── findings (round + 1) ◄──────────┤
                                                                                │ CLEAN
                     learner ◄─ deploy-sentinel ◄─ merge ◄─ nurses ◄─ PR ◄──────┘
```

The loop stops on its own only when the verifiers pass everything. A valve
escalates instead after five rounds, a repeated finding, or a blown budget;
the dashboard shows the one question that unblocks it.

## State and config

Everything lives under `$FACTORY_HOME` (default `$HOME/.factory`), never in
a repository:

```
$FACTORY_HOME/
  config.json  profile.md  _dashboard.md  _heartbeat.json
  _repos/      _epics/     _lessons/      _drafts/   tickets/
  <KEY>/       status.json  run.log  intake.md  spec.md  build/  verification/  pr.md  …
```

`config.json` has a default for every key (gates, budgets, personas, models,
parallelism, heartbeat intervals, `offline`). `/intake-oss config` prints the
effective values and where each came from. The learner may change a few
marked keys and lists every change on the dashboard. Schemas:
`skills/pipeline/references/config-schema.md` and `state-schema.md`.

## Profiles

`profile.md` has one section per capability with a `tool:` line
(`mcp:<tool>`, `cli:<command>`, `skill:<name>`, `builtin:<name>`, `none`),
an auth state, operation overrides, free-text notes the engine reads at run
time, and a `## Gaps` list. The schema is
`skills/pipeline/references/profile-schema.md`.

`/intake-oss` generates its profile. A vendor front door ships a
hand-written one instead: its own `SKILL.md` with a classifier for its hosts,
a `references/<vendor>/profile.md` it copies into `$FACTORY_HOME`, and data
files the profile points at (flake patterns, metric names, tracker
hierarchy). The engine reads the profile and the files; it never learns the
vendor's name. A vendor-specific front door of that shape lives in its own
repository and vendors this engine next to it.

Trackers without a hosted option fall back to the file tracker
(`skills/intake-oss/references/file-tracker.md`): one markdown file per
ticket under `$FACTORY_HOME/tickets/`, keys `LOCAL-n`, every tracker
operation mapped to a file edit.

## Degradation

A missing capability disables the stages that need it and says so on the
dashboard. Required capabilities stop the run with a message naming them.

| Capability | When `none` |
|---|---|
| `tracker` | file tracker; never `none` |
| `sources` | `WebFetch` for every URL; unreadable sources listed as gaps |
| `pr` | run stops before the PR stage |
| `chat` | terminal output only; no chat intake |
| `code` | local `rg` in the checkout |
| `ci` | build nurse records "no CI" once; PR checks still read |
| `obs` | deploy sentinel skipped; `measure` tickets get a "would measure" comment and a gate |
| `deploy` | sentinel window starts at merge |
| `incidents` | sentinel omits the incident check |
| `dispatch` | tickets run sequentially |
| `knowledge` | web search when available, else skipped |
| `design` | UX reviewer skips design-system checks |
| `voice` | the engine's own prose rules |

## Site

An animated explainer of the loop lives in `site/` (a Zola site) and is
published to GitHub Pages at <https://oh-eight.github.io/agent-factory/> by
`.github/workflows/pages.yml` on every push to `main` that touches `site/`.
Pages must be set to deploy from GitHub Actions once in the repository
settings. Locally:

```bash
zola --root site serve    # http://127.0.0.1:1111
zola --root site build    # writes site/public/ (ignored by git)
```

## Lints and the toy repo

```bash
tests/lint.sh          # name/dir match, SKILL.md length, home paths, secrets, vendor words, role headers
tests/toy-repo.sh      # creates $HOME/tmp/pipeline-toy (a sum CLI with two tests); --reset to recreate
```

The toy repo has one deliberate gap: `sum.py` does not handle non-numeric
input. Run `/intake-oss "add a sum command that adds its integer arguments"`
from inside it with `config.offline` true; round 1 should find the gap and
round 2 should be clean.

## Contributing a reference edit

Behaviour lives in `skills/<name>/references/*.md` and
`skills/<name>/agents/*.md`; `SKILL.md` files are the short workflow and
rarely change. The learner opens draft PRs here when a lesson repeats, each
touching only `references/` and citing the lesson file. Human edits follow
the same path: change the reference, run `tests/lint.sh`, open a PR that
says which run or lesson motivated it. Keep `SKILL.md` under 500 lines,
keep the engine vendor-free (the lint enforces the word list), and put
anything a role must know into the role's file rather than the skill that
spawns it.
