# Dashboard (`<front door>` with no argument)

Render `_dashboard.md` from state, print it, then resume anything resumable.
Keep it to one screen when the factory is quiet.

```markdown
# Factory — <iso time>   profile: <name>   heartbeat: <last tick, loop state>

## Needs you
| Key | Waiting on | Question | Resume |
|---|---|---|---|
| ABC-12 | gate merge | PR #41 green, sanity MATCH, 1 approval. Merge? | `/intake ABC-12 go` |
| ABC-9  | escalated  | C4 fails twice: should empty input be an error or 0? | `/intake ABC-9 "<answer>"` then `go` |

## Running
| Key | Mode | Stage | Round | Last event | Next |
|---|---|---|---|---|---|

## Waiting on others
| Key | PR | CI | Review | Approvals |
|---|---|---|---|---|

## Epics
| Epic | Done | Ready | Running | Blocked | Gated |
|---|---|---|---|---|---|

## Gaps
- obs: none → deploy-sentinel skipped for ABC-12, ABC-9
- unanswered: default_project (set with `/intake config default project ABC`)

## Learned since last view
- default_project set to ABC (3 runs)
- draft PR gero-factory#7: attack-catalogue, two new fuzzer cases

## Recently done
| Key | Finished | Rounds | PR | Sentinel |
```

Omit empty sections. "Needs you" always comes first. Every row in it has a
copy-pasteable command.

## Resume step

After printing: for each run whose lock is older than 2 hours with no
progress, or whose gate received an instruction, run `pipeline KEY`. Say
which runs were resumed in one line.
