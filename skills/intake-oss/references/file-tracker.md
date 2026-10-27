# File tracker

The tracker of last resort, and the one `config.offline` uses. One markdown
file per ticket under `$FACTORY_HOME/tickets/`, same fields as a hosted
ticket, so every downstream stage behaves the same. The engine never knows
it is talking to files: the profile says `tool: file` under `## tracker`,
and this document is the implementation.

## Layout

```
$FACTORY_HOME/tickets/
  .next                 # the next integer to allocate, one line
  LOCAL-1.md
  LOCAL-2.md
```

## Ticket file

```markdown
---
key: LOCAL-7
summary: Reject non-numeric arguments in sum
status: open                  # open | in_progress | in_review | done | cancelled
type: item                    # item | container
issue_type: bug               # bug | task | story | container (free text, informational)
labels: [factory-mode:code]
parent: LOCAL-5               # or null
links:
  - {type: blocks, key: LOCAL-8}
  - {type: relates, key: LOCAL-2}
assignee: null
created: 2026-10-21T02:12:00Z
updated: 2026-10-21T02:40:00Z
url: $HOME/.factory/tickets/LOCAL-7.md
---

## Problem
…

## Context
…

## Out of scope
…

## Open questions
…

## Acceptance criteria
- AC-1: …

## Comments
### 2026-10-21T02:40:00Z factory
Branch `gero/local-7-reject-non-numeric` in `$HOME/tmp/pipeline-toy`.
```

The body sections are those of `ticket-template.md`. `## Comments` is
appended at the end and is created on the first comment.

## Key allocation

```bash
dir="$FACTORY_HOME/tickets"; mkdir -p "$dir"
[ -f "$dir/.next" ] || echo 1 > "$dir/.next"
n=$(cat "$dir/.next"); key="LOCAL-$n"
echo $((n + 1)) > "$dir/.next.tmp" && mv "$dir/.next.tmp" "$dir/.next"
```

Keys are never reused, including for cancelled tickets. A missing `.next`
is rebuilt as one more than the highest existing `LOCAL-n`.

## Operation mapping

| Capability operation | File action |
|---|---|
| `get(key)` | read `tickets/<key>.md`; front matter becomes the fields, body stays markdown; `status_category` is `status` mapped to `open`, `in_progress`, `done` (`in_review` → `in_progress`, `cancelled` → `cancelled`) |
| `search(query)` | `grep -il` each query word over `tickets/*.md`; rank by how many words hit the front matter (`summary:`) before the body; return key, summary, status |
| `create(fields)` | allocate a key, write the file whole (`.tmp` then `mv`) with `created` and `updated` now, `status: open`; return key and `url` |
| `update(key, fields)` | rewrite the front-matter lines named in `fields`, or the body section named (`## Acceptance criteria`), set `updated` |
| `comment(key, text)` | append `### <iso> factory` and the text under `## Comments` (create the section if absent); set `updated` |
| `transition(key, state)` | set `status:` to the engine state (`in_progress`, `in_review`, `done`); never move backwards (a `done` ticket stays done; record a gap instead) |
| `link(a, type, b)` | append `{type, key: b}` to `a`'s `links` and the inverse (`blocks` ↔ `blocked_by`, `relates` ↔ `relates`) to `b`'s |
| `children(key)` | every file whose `parent:` equals `key`; return the fields `children` promises in `capabilities.md`, with `links[]` and `labels[]` from front matter |
| `hierarchy_level(key)` | `type: item` → 0; `type: container` → 1; a container whose children include a container → 2 |
| `labels(key, add[], remove[])` | edit the `labels:` list; keep order of first appearance |
| `types(project)` | always `[bug, task, story, container]` |

`project` is ignored; the file tracker has one project named `LOCAL`.
`tracker.get` on a hosted key (`ABC-12`) while the profile tracker is `file`
returns not found, and the classifier treats the token as free text.

## Concurrency

Two sessions may write at once (a dispatched run and the heartbeat). Every
write is whole-file through `.tmp` and `mv`. Key allocation reads and writes
`.next` in one short step; a collision (two files with the same key) is
detected on the next `create` and repaired by renumbering the newer file and
rewriting any `parent:` or `links:` that pointed at it.

## What the dashboard shows

Tickets created here appear with their `LOCAL-n` key and the file path as
the URL. `config` lists `tracker: file (N tickets)` so it is never mistaken
for a hosted tracker.
