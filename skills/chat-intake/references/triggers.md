# Triggers, ambiguity, replies, seen.json

## Trigger rules

Evaluate in order; the first match decides.

| # | Condition | Result |
|---|---|---|
| 1 | author is `self` | skip (self) |
| 2 | message is a reply inside a thread (has `thread_ts` and it differs from `ts`) | skip (reply) unless its parent is `pending` → reply-to-pending |
| 3 | `threads[ts].state` is `ticketed`, `skipped`, `failed` or `expired` | skip (seen) |
| 4 | `self` already replied in the thread | mark `ticketed`, `key: unknown`; skip (handled) |
| 5 | text starts with or contains `no-intake`, `skip:` or `not a ticket` | mark `skipped`; skip (author opt-out) |
| 6 | channel kind is `dm` and text contains neither `intake:` nor the front door name | skip (dm without trigger) |
| 7 | text is a bare link with no words, or a bare reaction/emoji, or under 4 words | skip (too short), unless it contains `intake:` |
| 8 | channel kind is `channel` | trigger |
| 9 | channel kind is `dm` and the text contains `intake:` or the front door name | trigger, with the trigger word removed from the brief |

A `trigger` means the top-level message plus its thread is one brief. A
message edited after it was ticketed is not re-triggered. A top-level
message deleted before the pass is never seen and nothing is posted.

`intake: retry` as a reply in a `failed` thread re-runs step 5 once for
that thread.

## Ambiguity rule

The front door's classifier answers `ambiguous: <question>` when it cannot
settle intent (`new`, `resume`, `epic`, `batch`) or project with one best
guess, or when the brief names two unrelated changes. `chat-intake` asks
exactly that question, once, in the thread, addressed to the author. The
author's first reply is appended to the brief under `## Clarification`
and the brief is resubmitted. A second `ambiguous:` on the same thread is
answered with the best-guess line (the front door includes `guess: <...>`
after the question) and the thread is marked `skipped` with the reason;
chat-intake never asks twice.

## Brief template (sent as the front door's `<text>`)

```markdown
<message text, verbatim>

## Thread
- <author> (<ts>): <reply text>

## Links
- <url>   # one per line, from the message and the replies, in order

## Clarification          # only after a pending thread is answered
- <author> (<ts>): <reply text>

source: <permalink>
intake-context: chat-intake channel=<channel> thread=<thread_ts> author=<author> unattended=true auto=<true|false> stop_after_ticket=<true|false>
```

The front door treats `source:` as a fetched source (the thread is the
brief's origin), reads `intake-context` to know no human is typing (gates
and questions follow the unattended path in `gates.md`), and when
`stop_after_ticket=true` (set when `auto` is on) stops after the ticket so
the factory dispatches it from the label. It returns one of:

```
ticket: KEY <url>            # repeated per ticket for a batch or epic
ambiguous: <question>  guess: <best guess>
error: <one line>
```

## Reply templates (chat register, after `voice.polish`)

Ticketed:

```
Filed as KEY: <url>
Running now; I will post the PR here when it exists. Reply `<front door> KEY stop` in this thread to stop it.
```

Ticketed with `auto`:

```
Filed as KEY: <url>
Queued for the factory (label factory-auto). Reply `<front door> KEY stop` to pull it.
```

Batch or epic:

```
Filed as EPIC-KEY with <n> children: <url>
The plan is in the epic comment; children run in dependency order.
```

Pending:

```
<author> one question before I file this: <question>
Reply in this thread; I pick it up on the next pass.
```

Failed:

```
Could not file this: <first line of the error>
Reply `intake: retry` after the fix, or file it by hand.
```

Expired:

```
No answer in <passes> passes, so I stopped watching this thread. Post again, or reply `intake: retry`, to restart.
```

Rules: the ticket key and link come first; never more than four lines;
no headings, emoji, or sign-off; `voice.polish(chat)` runs before posting
and never changes the key or the link.

## `seen.json`

```json
{
  "self": "U0123ABC",
  "last_pass": "2026-10-21T09:30:00Z",
  "channels": {
    "C0ABCDEF": {
      "kind": "channel",
      "auto": false,
      "last_ts": "1761037800.000100",
      "threads": {
        "1761037000.000200": {
          "state": "ticketed",
          "keys": ["ABC-123"],
          "urls": ["https://…/ABC-123"],
          "author": "U0456DEF",
          "replied_ts": "1761037100.000300",
          "brief": "_chat/briefs/C0ABCDEF-1761037000.000200.md"
        },
        "1761037500.000400": {
          "state": "pending",
          "question": "Is this for project ABC or XYZ?",
          "guess": "ABC",
          "author": "U0789GHI",
          "asked_ts": "1761037600.000500",
          "replied_ts": "1761037600.000500",
          "passes": 2,
          "brief": "_chat/briefs/C0ABCDEF-1761037500.000400.md"
        }
      }
    }
  }
}
```

| Field | Meaning |
|---|---|
| `self` | the factory's chat user id from `chat.whoami()` |
| `last_pass` | when the last pass finished; the heartbeat uses it for the interval |
| `channels.<id>.kind` | `channel` or `dm`; from the config entry, default `channel` |
| `channels.<id>.auto` | effective auto flag at the last pass |
| `channels.<id>.last_ts` | newest message `ts` read, skipped or not; the next `chat.read` starts here |
| `threads.<thread_ts>.state` | `ticketed`, `pending`, `skipped`, `failed`, `expired` |
| `threads.<thread_ts>.keys`, `urls` | tickets created for this thread; `["unknown"]` when only the factory's reply proves it |
| `threads.<thread_ts>.question`, `guess`, `asked_ts`, `passes` | the pending state |
| `threads.<thread_ts>.replied_ts` | last reply the factory posted in this thread; guards against double posts |
| `threads.<thread_ts>.brief` | path of the brief file under `$FACTORY_HOME` |

Threads older than 30 days with a terminal state may be pruned on write;
`last_ts` is never moved backwards. `--dry-run` writes to
`seen.json.dry-run` instead.
