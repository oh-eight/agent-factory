# Harness notes

The engine runs in Claude Code first, and degrades in Cursor and Codex.
Detect the harness at the start of every front-door run and record it in
`status.json.harness` and the profile's `## Harness` section.

| Need | Claude Code | Cursor / Codex |
|---|---|---|
| Spawn a role in a fresh context | `Agent` tool: `subagent_type: general-purpose`, `model` from `governor.md`, prompt = the role file's text followed by an `## Inputs` block | No subagents. Read the role file and follow it in the current session as if you were that role; write its output file before starting the next role |
| Invoke another skill | `Skill` tool | Read that skill's `SKILL.md` and follow it inline |
| Recurring passes | `loop` skill (`/loop 15m <front door> tick`), else `CronCreate` with the same prompt | Tell the user to run `<front door> tick` by hand or from a shell loop |
| MCP tools | `mcp__<server>__<name>`; the prefix is in the profile | Tool names as the harness shows them; the profile's `mcp_prefix` may be empty |
| Ask the user | `AskUserQuestion` | Plain question in the reply, then stop |

## Spawning a role

```
Agent(
  subagent_type: "general-purpose",
  model: <from governor.md>,
  description: "<role> for <KEY>",
  prompt: <full text of skills/<skill>/agents/<role>.md>
          + "\n\n## Inputs\n" + one `- name: /absolute/path or value` line per input
)
```

Subagents inherit nothing: no conversation, no skills, no open files. Pass
absolute paths. Every role file starts with the same header rule: "You
receive an `## Inputs` block after this text. If any input is missing, stop
and say which." Every role returns under 30 lines; detail goes to the
output file named in its inputs.

## Isolation in sequential mode

When roles run in the same session, the verifier's isolation is weaker: the
session has already seen the code. Follow the verifier's forbidden list
strictly anyway, record `isolation: same-session` in the report header, and
say so on the dashboard. A same-session CLEAN still counts, with that label.

## Shell notes

- Use temp files, not shell variables, for any text that may contain
  newlines or JSON (zsh `echo` rewrites `\n`).
- Capture stderr separately from stdout when parsing tool output.
- Write state files whole: write to `<file>.tmp`, then `mv`.
