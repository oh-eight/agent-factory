---
name: learner
description: Closes the loop after a run. Spawns the retrospector over one run's state directory to write a dated lesson file, keeps _lessons/INDEX.md current, applies config-only lessons straight away, and turns skill-text lessons that repeat into draft PRs against the repository that owns the reference file. Invoked by `pipeline` at stage learn or by the heartbeat; run by name only to debug (`learner KEY`, `learner --all`).
argument-hint: "<KEY> | --all [--force]"
metadata:
  tags: [factory, engine, learning, self-improvement]
---

# Learner

Every run leaves evidence: which attack found a bug, which test flaked,
which claim the spec missed, what the builder had to discover that the
repository map should have told it. The learner turns that into three
kinds of change, in increasing order of caution: a lesson file (always), a
config or data edit (immediately, when allowed), and a draft PR against a
skill repository (only when a lesson repeats, never merged by the factory).

Read before acting: `pipeline/references/state-schema.md`,
`pipeline/references/config-schema.md`, `pipeline/references/capabilities.md`,
`pipeline/references/pr-template.md`, `agents/retrospector.md`.

## Entry forms

```
learner KEY            one run; skipped when _lessons/<date>-KEY.md exists (--force rewrites)
learner --all          every <KEY>/ with stage done or escalated and no lesson file, then aggregate
```

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `learner.apply_config` | true | edit learnable config keys and data files now |
| `learner.open_prs` | true | open draft PRs for repeated skill lessons |
| `learner.branch_prefix` | `config.branch_prefix` | prefix for learner branches |
| `skill_repos.engine` | `gero-factory` | URL or path of the repository that owns engine skills |
| `skill_repos.profile` | null | URL or path of the repository that owns the active profile and its data files |

`skill_repos` values are a clone URL or a local path. A bare name such as
`gero-factory` is resolved against the profile's `## pr` host, else treated
as a path under `$HOME`; when neither resolves, the PR path is skipped
with a gap. Engine skills: `pipeline`, `epic-intake`, `prepare`,
`spec-task`, `adversarial-review`, `build-nurse`, `pr-sanity-check`,
`review-nurse`, `deploy-sentinel`, `factory`, `learner`, `chat-intake`,
`intake-oss`. Any other skill, and every data file the profile points at by
absolute path, belongs to `skill_repos.profile`.

## Workflow

Copy this and track it:

```
- [ ] 1. Load config, profile, run list
- [ ] 2. Retrospector per run → _lessons/<date>-<KEY>.md
- [ ] 3. Rebuild INDEX.md
- [ ] 4. Apply config lessons
- [ ] 5. Apply data lessons to writable installed copies
- [ ] 6. Draft PRs for repeated skill lessons
- [ ] 7. Report
```

### 1. Load

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json` with
defaults, `profile.md`, `_lessons/INDEX.md` (create an empty one from the
shape below if missing). Run list: the given KEY, or for `--all` every
`$FACTORY_HOME/<KEY>/status.json` with stage `done` or `escalated` whose
key has no `_lessons/*-<KEY>.md`. For `learner KEY` with an existing lesson
and no `--force`, skip to step 3.

### 2. Retrospector

Spawn `agents/retrospector.md` (model `opus`, `config.models.retrospector`
overrides) per `pipeline/references/harness.md` with inputs:

| Input | Value |
|---|---|
| `state_dir` | `$FACTORY_HOME/<KEY>` expanded |
| `lessons_index` | `$FACTORY_HOME/_lessons/INDEX.md` |
| `profile` | `$FACTORY_HOME/profile.md` |
| `config` | `$FACTORY_HOME/config.json` |
| `repos_dir` | `$FACTORY_HOME/_repos` |
| `skill_repos` | the resolved engine and profile repository identifiers |
| `engine_skills` | the list above |
| `output` | `$FACTORY_HOME/_lessons/<YYYY-MM-DD>-<KEY>.md` |

Append `{stage: "learn", role: "retrospector", model, started, ended}` to
`<KEY>/costs.json`. On return, confirm the file has every section the role
file names; a missing section → re-prompt once naming it. `--all` runs the
retrospectors one at a time.

### 3. Rebuild INDEX.md

Recompute from every `_lessons/*-*.md`, never increment: parse each
`fingerprint:` line under `## Skill lessons` and `## Config lessons`, count
occurrences, first and last date, the lesson files. Preserve `status` and
`pr` columns from the existing INDEX for fingerprints that already have
them; new fingerprints start `proposed`. Also keep `## Applied` and
`## PRs` lists. Write whole (`.tmp`, `mv`).

```markdown
# Lessons index
updated: <iso>

## Fingerprints
| Fingerprint | Kind | Count | First | Last | Status | Target | PR | Lessons |
|---|---|---|---|---|---|---|---|---|
| spec-empty-input-claim | skill | 2 | 2026-10-02 | 2026-10-21 | pr-open | engine:skills/spec-task/references/claim-checklist.md | <url> | 2026-10-02-ABC-1.md, 2026-10-21-ABC-9.md |
| config-default_project | config | 3 | … | … | applied | config.json | | … |

## Applied
- <date> default_project: ABC — 3 runs inferred the same project (2026-10-21-ABC-9.md)

## PRs
- <date> <url> draft, fingerprints: …
```

`Status` ∈ `proposed | applied | pr-open`. The dashboard's "Learned since
last view" reads `## Applied` and `## PRs` entries dated after
`_heartbeat.json.last_view`.

### 4. Apply config lessons

Skip unless `config.learner.apply_config`. For each `## Config lessons`
line `key: value — evidence` in the new lesson files:

- Only keys marked learnable in `config-schema.md`: `default_project`,
  `repos.<component>`, `burn_in_runs`, `sentinel.window_minutes`. Anything
  else stays `proposed` with `note: not learnable`.
- `default_project` and `repos.*` apply at count ≥ 2 across lessons;
  `burn_in_runs` and `sentinel.window_minutes` at count ≥ 2 and only in
  the direction the evidence says (more runs when flakes slipped through,
  a longer window when an anomaly came late). Never below the schema
  default for `burn_in_runs`.
- Edit `config.json` whole, record `learned on <date>` per key in a
  `_learned` map inside the file (so `<front door> config` can show the
  source), set `Status: applied`, append to `## Applied`.

### 5. Apply data lessons

Four append-only targets, each a `## Learned` (or `## Flake history`)
section with dated one-line entries `- <date> <KEY>: <text>`:

| Lesson section | Target |
|---|---|
| Flakes seen | `_repos/<owner>-<repo>.md` `## Flake history`, and the file named by the profile's `## ci` `flake_patterns:` under `## Learned` |
| Cartography gaps | `_repos/<owner>-<repo>.md` `## Flake history`'s sibling `## Learned` (create under the area when missing) |
| Sentinel signals that fired or missed | the profile's signals file (`## obs` `signals:`), `## Learned` |
| What found bugs | the engine's `adversarial-review/references/attack-catalogue.md`, `## Learned` |

`_repos/` is always writable. For the other three, write to the installed
copy only when both hold: `test -w <file>` succeeds, and the first five
lines of the file do not contain `vendored from`. Otherwise do not touch
it; add the entry to the lesson's `## Skill lessons` with the target path
so step 6 carries it. Never add a line whose text already exists in the
section.

### 6. Draft PRs for repeated skill lessons

Skip unless `config.learner.open_prs`. Select fingerprints of kind `skill`
with `Count ≥ 2` and `Status: proposed`. Group by target repository
(`engine:` or `profile:` prefix in `Target`). Per repository with at least
one selected lesson:

1. Clone or pull into `$FACTORY_HOME/_self/<repo-name>/` (`git clone
   <url or path>`; if present, `git checkout <default branch> && git pull
   --ff-only`). A dirty tree there → stop for this repo, record a gap.
2. Branch `<learner.branch_prefix>learner-<YYYY-MM-DD>`; if it exists
   locally or on origin, check it out and pull.
3. Apply every selected lesson's `proposed text` to its target file,
   which must match `skills/*/references/*.md`. A target that does not
   exist, or that is `SKILL.md`, an `agents/*.md`, or outside
   `references/`, is skipped and left `proposed` with a note. Insert
   under the section the lesson names, else under `## Learned` at the end.
   Skip a lesson whose text is already present.
4. Nothing changed → clean up the branch and continue to the next repo.
5. Commit: subject `learner: <n> repeated lessons for <skills>`; body
   lists each fingerprint with its lesson file paths. Push the branch.
6. `pr.create(base: default branch, head: branch, title, body, draft:
   true)` with the body from `pipeline/references/pr-template.md`:
   Problem = the repeated lesson(s) in one paragraph each with counts;
   Solution = the reference edit, by file and section; Testing = "n/a,
   documentation change; the next run that hits this fingerprint is the
   test"; Context = the lesson file paths. Run `voice.polish(durable)`.
   When the branch already has an open PR, `pr.edit` its body instead.
7. Set `Status: pr-open`, `PR: <url>` for each fingerprint; append to
   `## PRs`.

`config.offline`: do everything up to the commit, skip push and
`pr.create`, record `pr: offline` in the index.

### 7. Report

Print under 15 lines: lesson files written, fingerprints new and repeated,
config keys applied, data files appended, PRs opened or updated, gaps. The
`pipeline` final report quotes the first line.

## Harness notes

Without `Agent`, read `agents/retrospector.md` and follow it in this
session, writing the lesson file before continuing. Without `pr.create`
in the profile, stop after the commit and print the push and PR command
for the user. MCP tools use the prefix from the profile's `## Harness`
section.

## Hard rules

- Never call a vendor tool by name; go through the profile.
- Never merge a PR, never push to a default branch, never force-push.
- Never edit `SKILL.md` or `agents/*.md` in any repository; only
  `skills/*/references/*.md`, and only with a lesson citation in the
  commit body.
- Never edit a vendored or read-only installed copy; carry the lesson to
  the owning repository instead.
- Only learnable config keys change; every change is listed in
  `## Applied` and shown on the dashboard.
- Never write outside `$FACTORY_HOME`, the installed data files named
  above, and `_self/<repo>/`.
- One lesson file per run per date; re-runs rewrite only with `--force`.
