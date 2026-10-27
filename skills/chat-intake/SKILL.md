---
name: chat-intake
description: Watches configured chat channels and turns each new top-level message into a ticket through the front door, replying in the thread with the key or with one clarifying question. Keeps per-channel watermarks and a thread-to-ticket map in _chat/seen.json so no thread gets two tickets. Invoked by the heartbeat for every entry in config.chat_channels, or by a front door; run by name only to debug (`chat-intake <channel>`).
argument-hint: "[<channel>] [--auto] [--dry-run]"
metadata:
  tags: [factory, engine, intake, chat, heartbeat]
---

# Chat intake

A channel is a queue. Each message that passes `references/triggers.md`
becomes a brief, goes through the front door's classify-and-run path with
the thread permalink as a source, and gets exactly one reply in its own
thread: the ticket key and link, or one question when the classifier
cannot decide. Everything it remembers is in
`$FACTORY_HOME/_chat/seen.json`.

Read before acting: `references/triggers.md`,
`pipeline/references/capabilities.md` (`chat`), `pipeline/references/prose.md`
(`chat` register), `pipeline/references/hygiene.md` (labels).

## Entry forms

```
chat-intake                 one pass over every channel in config.chat_channels
chat-intake <channel>       one pass over one channel
chat-intake <channel> --auto      also label created tickets factory-auto
chat-intake <channel> --dry-run   read and classify, post nothing, write seen.json to .dry-run
```

The front door name comes from `config.front_door` (for example `/intake`
or `/intake-oss`).

## Workflow

Copy this and track it:

```
- [ ] 1. Load config, profile, seen.json
- [ ] 2. Read new messages
- [ ] 3. Apply the trigger rules
- [ ] 4. Re-check pending threads
- [ ] 5. Brief and front door per trigger
- [ ] 6. Reply in the thread
- [ ] 7. Write seen.json and report
```

### 1. Load

`FACTORY_HOME="${FACTORY_HOME:-$HOME/.factory}"`. Load `config.json` with
defaults and `profile.md`. `## chat` `tool: none` → print `chat-intake:
no chat capability` and stop; nothing to read. Record the factory's own
user via `chat.whoami()` (cached in `seen.json.self`). Channels: the
argument, else `config.chat_channels[]` (each entry is a channel id or
name as the profile's chat tool expects, optionally `{channel, auto,
kind: channel|dm}`). Load `_chat/seen.json` or create it from the schema
in `triggers.md`. `auto = --auto || config.chat_auto_dispatch || the
channel entry's auto`.

### 2. Read new messages

Per channel: `chat.read(channel, since: last_ts)`; on a first pass
`since` is now minus `config.chat_backfill_minutes` (default 60), so a
fresh channel does not turn its history into tickets. Keep for each
message: `ts`, `thread_ts`, `author`, `text`, `permalink`, `reactions`,
and for top-level messages their replies. Drop messages whose author is
`self`. Sort by `ts`.

### 3. Apply the trigger rules

Follow `triggers.md` literally. The result per message is `trigger`,
`skip (reason)` or `reply-to-pending`. A thread already in
`seen.json.threads` with `state: ticketed` is never a trigger again; a
thread where `self` already replied is marked `ticketed` with
`key: unknown` and skipped (the map was lost, not the ticket).

### 4. Re-check pending threads

For each `threads[thread_ts]` with `state: pending`: read the thread's
replies since `asked_ts`. A reply from the original author (or anyone
when the channel entry says `anyone_may_answer`) → append it to the brief
under `## Clarification` and treat the thread as a trigger in step 5. No
reply → `passes += 1`; after `config.chat_pending_passes` (default 14)
set `state: expired`, post the expiry line from `triggers.md`, and stop
watching it.

### 5. Brief and front door

Build the brief per the template in `triggers.md`: the message text, the
thread replies in order with authors, every link found (one per line),
the permalink as `source:`, and the trailer that tells the front door it
is unattended and whether to stop after the ticket. Write it to
`_chat/briefs/<channel>-<thread_ts>.md`.

Invoke the front door with the `Skill` tool: `<front door> <brief text>`.
The front door classifies, dedupes against the tracker, drafts the ticket,
and either creates it and continues per its own rules, or answers with
`ambiguous: <one question>`. Read its return:

- `ticket: KEY <url>` (one or several) → `state: ticketed`, record keys
  and urls. With `auto`, `tracker.labels(KEY, add: [factory-auto])` for
  each key (only `factory` and `epic-intake` otherwise own labels; this
  is the one exception, and the front door may have done it already).
- `ambiguous: <question>` → `state: pending`, store the question,
  `asked_ts`, `author`, `passes: 0`.
- anything else, or an error → `state: failed` with the first line of
  the error; reply with the failure template; the next pass does not
  retry unless the author replies.

`--dry-run` or `config.offline`: print the brief and the classification
the front door would receive, create nothing, post nothing.

### 6. Reply in the thread

One `chat.reply(thread_ts, text)` per thread per state change, after
`voice.polish(text, chat)`, using the templates in `triggers.md`:
ticketed (key, link, what happens next, how to stop it), pending (the one
question, who should answer), failed (what went wrong, how to retry by
replying `intake: retry`), expired. Record `replied_ts` so a crash after
the reply does not post twice. Never post anywhere except the triggering
thread; never DM from this skill.

### 7. Write and report

Update `last_ts` per channel to the newest message read (even when it was
skipped), write `seen.json` whole (`.tmp`, `mv`). Print one line per
channel: `chat-intake <channel>: read <n>, triggered <n>, ticketed <keys>,
pending <n>, skipped <n>`; nothing new → `chat-intake <channel>: idle`.

## Heartbeat contract

`pipeline tick` calls `chat-intake` with no argument when
`config.chat_channels` is non-empty and `heartbeat.chat` minutes have
passed since `seen.json.last_pass`. Two passes in a row with no new
messages make no call except `chat.read` and change nothing.

## Harness notes

Without `Skill`, read the front door's `SKILL.md` and follow its
classify path inline for each brief. Without a chat tool in the profile
the skill exits at step 1. MCP tools use the prefix from the profile's
`## Harness` section.

## Hard rules

- Never call a vendor tool by name; go through the profile's `## chat`.
- Never post outside the triggering thread; one reply per state change.
- Never create two tickets for one thread; the `threads` map is the
  record, and a thread where `self` already replied counts as handled.
- Never turn a message from `self`, a reply inside an existing thread, or
  a message the author marked to skip into a ticket.
- Never read further back than `last_ts`, or the backfill window on a
  first pass.
- Never write outside `$FACTORY_HOME/_chat/`.
- Replies use the `chat` register: the answer first, under four lines,
  no headings, no sign-off.
