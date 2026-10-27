# Fetching sources

Every link in a brief, ticket, epic or chat thread is fetched once and saved
under the run's `sources/` directory. Later stages read the saved file, not
the network, so a run can be resumed offline and the verifier never sees a
source it should not.

## Dispatch

Read the profile's `## sources` section. It lists host patterns and the
tool for each. Match the URL's host (longest pattern first), call the tool,
and convert the result to markdown. When no pattern matches, use the `"*"`
entry (normally `builtin:WebFetch`). When the fetch fails, save a stub with
the error and list the URL under `## Gaps` in `intake.md`.

Tracker keys found in text (`[A-Z][A-Z0-9]+-\d+`, `#\d+`,
`owner/repo#\d+` depending on the profile's tracker) are also sources:
fetch with `tracker.get` plus comments.

Shortened links are resolved before matching when the profile names a
resolver for that host.

## File shape

`sources/NN-<slug>.md`, numbered in the order the links appeared:

```markdown
---
url: <original url>
resolved: <final url if different>
kind: design | doc | thread | page | ticket | pr | build | web
fetched: <iso time>
tool: <profile tool used>
---

## Relevance
<One line: what in this source matters for the brief.>

## Extract
<The content, trimmed to what matters. Presentations: one section per page
with speaker notes. Threads: author, time, text per message, replies
indented. Tickets: summary, description, acceptance criteria, comments.
PRs: title, body, file list, review summary. Keep tables as tables.>
```

Keep extracts under roughly 400 lines; link to the original for the rest and
say what was cut.

## Budget

- Fetch every link the author gave. Those are not optional.
- Secondary links found inside a source are fetched only when the brief
  cannot be understood without them, up to five per run; list the rest under
  `## Not fetched` in `intake.md`.
- Never fetch the same URL twice in a run; check `sources/` first.
