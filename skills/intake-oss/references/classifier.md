# Classifier

Two passes. The first is mechanical and never wrong about what a token is.
The second is judgement about what the user wants done with it. Both finish
before any write.

## Pass 1: patterns → kinds

Split the argument on whitespace. Strip surrounding quotes and angle
brackets. Match each token in this order; the first match wins. Unmatched
tokens are joined back into one free-text brief.

### Keys

| Pattern | Kind | Fetch with |
|---|---|---|
| `^[A-Z][A-Z0-9]+-\d+$` | tracker item or container (ask `tracker.hierarchy_level`) | `tracker.get`; `LOCAL-n` keys go to the file tracker |
| `^#\d+$` | tracker item in the current repository's issue tracker | `tracker.get` with the repository from `git remote` |
| `^[\w.-]+/[\w.-]+#\d+$` | tracker item or PR (the host decides which when fetched) | `tracker.get`, then `pr.view` if the tracker says it is a PR |

### Hosts

Match the URL host and path. Hosts that discovery found are in the profile's
`## sources` section; this table lists the generic ones so the classifier can
name the kind even for a host the profile has no tool for (then the fetch
falls back to `builtin:WebFetch`).

| Host and path | Kind |
|---|---|
| `*.atlassian.net/browse/<KEY>` | tracker item or container |
| `*.atlassian.net/jira/software/*/boards/*/backlog?selectedIssue=<KEY>` | tracker item |
| `*.atlassian.net/wiki/*` | doc |
| `linear.app/<team>/issue/<KEY>` | tracker item |
| `linear.app/<team>/project/*` | container |
| `github.com/<o>/<r>/issues/<n>` | tracker item (container when the body has a task list of issue links) |
| `github.com/<o>/<r>/milestone/<n>`, `github.com/orgs/<o>/projects/<n>` | container |
| `github.com/<o>/<r>/pull/<n>` | PR |
| `github.com/<o>/<r>/actions/runs/<n>` | CI build |
| `github.com/<o>/<r>/discussions/<n>` | chat thread |
| `gitlab.com/<path>/-/issues/<n>` (and self-hosted hosts whose path has `/-/issues/`) | tracker item |
| `gitlab.com/<path>/-/epics/<n>`, `gitlab.com/groups/<g>/-/epics/<n>` | container |
| `gitlab.com/<path>/-/merge_requests/<n>` | PR |
| `gitlab.com/<path>/-/pipelines/<n>`, `/-/jobs/<n>` | CI build |
| `*.slack.com/archives/<C>/p<ts>` | chat thread (a channel link without `p<ts>` is a channel, treated as free text plus a source) |
| `discord.com/channels/<g>/<c>/<m>` | chat thread |
| `notion.so/*`, `*.notion.site/*` | doc |
| `docs.google.com/document/*`, `/presentation/*`, `/spreadsheets/*` | doc |
| `drive.google.com/*` | doc |
| `buildkite.com/<org>/<pipeline>/builds/<n>` | CI build |
| `circleci.com/pipelines/*` , `app.circleci.com/*` | CI build |
| any other `https?://` URL | doc (web page); fetched with the `"*"` source tool |

Hosts the profile lists under `## sources` with a tool override this table's
fetch method, never its kind.

### Output of pass 1

A list of `{token, kind, key or url}` plus one `free text` entry when
anything was unmatched. Fetch nothing yet except what pass 2 needs to decide
(the tracker item's level and status, the PR's author and branch, the build's
PR). Those reads are cheap and read-only.

## Pass 2: judgement → intent

Decide one intent for the whole line.

| Observation | Intent |
|---|---|
| A key or item whose `$FACTORY_HOME/<KEY>/status.json` exists | `resume` |
| Exactly one open PR, authored by the current user (`pr.view` author equals the profile's own login), nothing else on the line | `resume` (shipping stages: seed a run at `nurse` if none exists) |
| The user's own PR, already merged or closed | nothing to resume: say so; merged plus a `deploy` or `obs` capability → offer `deploy-sentinel` as the one question |
| A key-shaped token that `tracker.get` and the file tracker both reject | `unknown key`: ambiguous, one question (typo, other tracker, or new ticket) |
| A CI build URL alone, or with its PR | `resume` (build nurse on that PR) |
| A tracker item with `hierarchy_level >= 1`, or a container URL | `epic` |
| A tracker item with `hierarchy_level == 0` and no run | `new` from the ticket (no new ticket is created; `intake.md` is built from it) |
| Free text alone, or free text with sources (threads, docs, someone else's PR) | `new` |
| Free text whose sources describe several outcomes with no shared acceptance criteria, or a thread where distinct asks are made by distinct messages | `batch` |
| A brief that pass 2 sizes L or XL (several surfaces, a migration, a flag plus a bake, more than nine acceptance criteria) | `epic` (container ticket first) |
| Several tracker items on one line | `batch` of `resume`/`new` per item |

Ties and gaps go into one question:

- Two intents fit (a thread with a PR by someone else: source, or resume?).
- The ticket writer cannot infer a project (see `ticket-template.md`).
- `tracker.search` found a probable duplicate.
- A `go` or `stop` with no key when more than one run is gated.

Offer the best guess as the recommended option. One question per run.

## The reading

Print this block before any write. Three lines, no more:

```
reading: <n> input(s): <kind> <key or short id>[, …]
intent:  <new | resume | epic | batch> (<one clause of why>)
action:  <the next concrete step, with the key, slug or command>
```

Examples:

```
reading: 1 input: tracker item ABC-12 (level 0, open, no run)
intent:  new (ticket exists; brief built from it)
action:  intake.md, status.json, pipeline ABC-12

reading: 3 inputs: chat thread (12 messages), doc, free text
intent:  batch (the thread asks for a fix and a dashboard; the doc covers both)
action:  2 drafts in project OPS, gate ticket, then factory --label factory-auto

reading: 1 input: CI build 4412 on PR #91 (branch fix-upload)
intent:  resume (nurse)
action:  build-nurse https://…/runs/4412
```

If the reading is wrong, the user says so in the next message and the
front door recomputes with that message as an instruction; nothing was
written yet.
