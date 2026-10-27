# Capabilities

The engine never names a vendor tool. Every skill in this repo asks for a
*capability operation* such as `tracker.get` or `ci.retry`, and the active
profile (`$FACTORY_HOME/profile.md`, see `profile-schema.md`) says which
concrete tool implements it and how to call it.

Rules for skill authors:

- Write `tracker.comment(KEY, text)` in prose, never a vendor tool name such as `acme_add_comment`.
- Before using a capability, read the profile section for it. If the section
  says `tool: none`, follow the **Degradation** column below and record the
  gap in `status.json.gaps[]` so the dashboard can show it.
- A **required** capability with `tool: none` stops the run with a clear
  message naming the capability and how to fix the profile.
- Never invent an operation that is not in this table. If a stage needs
  something new, add it here first.

| Capability | Operations | Required | Degradation when `none` |
|---|---|---|---|
| `tracker` | `get(key)`, `search(query)`, `create(fields)`, `update(key, fields)`, `comment(key, text)`, `comment_update(key, comment_id, text)`, `comments(key)`, `transition(key, state)`, `link(a, type, b)`, `children(key)`, `hierarchy_level(key)`, `labels(key, add[], remove[])`, `types(project)` | yes | The front door falls back to the file tracker (`intake-oss/references/file-tracker.md`); a run never has `tracker: none` |
| `sources` | `fetch(url) → markdown` dispatched by host | yes | `WebFetch` for any URL; unreadable sources are listed as gaps in `intake.md` |
| `chat` | `dm(text)`, `reply(thread, text)`, `read(channel, since)`, `whoami()` | no | Terminal output only; `chat-intake` disabled |
| `code` | `search(query, repo?)`, `references(symbol)`, `definition(symbol)` | no | Local `rg` in the checkout; cross-repo questions become gaps |
| `pr` | `create(base, head, title, body, draft)`, `view(n)`, `diff(n)`, `files(n)`, `checks(n)`, `comments(n, since)`, `reviews(n, since)`, `reply(thread, text)`, `comment(n, text)`, `edit(n, title?, body?)`, `merge(n, strategy)`, `connect(n)`, `search(query)` | yes | None; the run stops before stage `pr` |
| `ci` | `status(pr)`, `failed_jobs(pr)`, `logs(job)`, `retry(job)`, `root_cause(build)` | no | `build-nurse` records "no CI" once and marks itself done; `pr.checks` is still read when it exists |
| `obs` | `metrics_range(query, from, to, step)`, `logs_count(query, from, to)`, `alerts_firing(service)`, `explore_link(query)` | no | `deploy-sentinel` skipped and reported; `measure` mode comments what it would measure and gates |
| `deploy` | `live_status(pr) → {live, at, version}` | no | Sentinel window starts at merge time |
| `incidents` | `list(service, since)`, `get(id)` | no | Sentinel omits the incident check |
| `dispatch` | `spawn(prompt, label) → handle`, `status(handle)`, `stop(handle)` | no | `factory` runs tickets sequentially in the current session |
| `knowledge` | `search(query)`, `read(id)` | no | `WebSearch` when available, else skipped |
| `design` | `components()`, `component(name)`, `tokens()` | no | UX reviewer skips design-system checks and says so |
| `voice` | `polish(text, register)` with registers `durable` (tickets, PRs, docs) and `chat` (DMs, replies) | no | Apply `prose.md` (the engine's own de-LLM rules) |

## Operation semantics that skills rely on

- `tracker.children(key)` returns direct children only, each with `key`,
  `summary`, `status`, `status_category` (`open|in_progress|done|cancelled`),
  `links[]` (`{type: blocks|blocked_by|relates, key}`), `labels[]`,
  `assignee`. Profiles say how children are attached (parent field, epic
  link, task list, sub-issue).
- `tracker.hierarchy_level(key)` returns `0` for a work item, `1` for a
  container of work items (epic, milestone, project), `2` for a container
  of containers (goal, initiative). Profiles map vendor types to these.
- "Owned comments" (one comment per ticket that the factory keeps current,
  found by its title line) use `tracker.comments` to find the id and
  `tracker.comment_update` to replace the text. A profile without
  `comment_update` posts a new comment only when the text changed and
  records a gap.
- `tracker.transition(key, state)` takes the engine states `in_progress`,
  `in_review`, `done`; the profile maps them to vendor transition names.
  Unknown mapping → comment instead of transition, and a gap.
- `pr.checks(n)` returns `[{name, state: pending|success|failure, url, job}]`.
- `ci.root_cause(build)` returns structured failures when the profile has a
  structured tool, else the tail of the failing log.
- `dispatch.spawn` must give the spawned run its own working copy of the
  repository and the prompt `<front door> KEY` so it starts from state.
- `voice.polish` never changes headings or template structure; it rewrites
  sentences inside them.

## Invocation forms

The profile's `tool:` line has one of these forms. Skills follow the form
literally:

| Form | Meaning |
|---|---|
| `mcp:<tool_name>` | Call the MCP tool. In Claude Code the full name is `mcp__<server>__<tool_name>`; the profile's `## Harness` section gives the prefix |
| `cli:<command template>` | Run with Bash; `{key}`, `{n}`, `{text}` placeholders are substituted; text goes through a temp file when it may contain newlines |
| `skill:<name>` | Invoke the skill with the `Skill` tool (sequentially inline in harnesses without it) |
| `builtin:<name>` | A harness tool such as `WebFetch`, `WebSearch`, `Agent` |
| `none` | Capability absent; degrade per the table |
