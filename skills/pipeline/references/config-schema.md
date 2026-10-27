# `config.json`

Lives at `$FACTORY_HOME/config.json`. Every key has a default, so an empty
file is valid. The front door bootstraps it on first run with one batched
question. The learner may change the keys marked **learnable**; it lists
every change on the dashboard.

| Key | Default | Learnable | Meaning |
|---|---|---|---|
| `profile` | front door decides | | `discovered` or a vendor profile name |
| `default_project` | null | yes | tracker project for new tickets when nothing else decides |
| `chat_user` | null | | own chat user id for DMs (probed via `chat.whoami`) |
| `notify.chat` | true when `chat` exists | | send DMs on state changes |
| `branch_prefix` | profile default, else `<git user>/` | | prefix for factory branches |
| `gates` | `["merge"]` | | see `gates.md` |
| `auto_merge` | false | | merge without the `merge` gate (ignored unless `gates` lacks `merge`) |
| `pr_ready` | false | | open PRs ready for review instead of draft |
| `parallel` | 2 | | dispatcher slots |
| `personas` | `["fuzzer","attacker","stranger"]` | | verifier personas per round |
| `mutation` | true | | run the mutation auditor |
| `burn_in_runs` | 5 | yes | times each new test is run for flakiness |
| `budget.max_rounds` | 5 | | see `governor.md` |
| `budget.max_inner_passes` | 3 | | |
| `budget.max_agent_spawns` | 60 | | |
| `budget.max_wall_minutes` | 240 | | |
| `models` | `{}` | | role → model overrides |
| `triage.defer_below` | `"medium"` | | findings strictly below this severity become follow-up tickets (`security` never) |
| `heartbeat` | `{nurse:15, sentinel:15, factory:30, chat:30}` | | minutes between passes |
| `chat_channels` | `[]` | | channels `chat-intake` watches |
| `learner.apply_config` | true | | let the learner change learnable keys |
| `learner.open_prs` | true | | let the learner open draft PRs against skill repos |
| `repos` | `{}` | yes | component or project → repository path mapping |
| `sentinel.window_minutes` | 120 | yes | post-deploy watch window |
| `cartography_ttl_days` | 14 | | re-map an area after this many days |
| `offline` | false | | no tracker, chat or PR writes; used for dry runs. Files are still written |
| `front_door` | set by the front door | | the command that owns this state (`/intake`, `/intake-oss`); used in resume commands, heartbeat prompts and dispatch prompts |
| `skill_repos.engine` | the `origin` remote of the checkout the engine skills are installed from (resolve the installed skill symlink, then `git remote get-url origin`) | | where the learner sends engine reference edits. A vendor front door that ships a vendored copy of the engine must set this explicitly at bootstrap (from its vendoring pin), since the default would resolve to the copy |
| `skill_repos.profile` | null | | where the learner sends profile data edits (a vendor front door sets it) |
| `learner.branch_prefix` | `branch_prefix` | | prefix for learner PR branches |
| `chat_auto_dispatch` | false | | chat-intake adds `factory-auto` to tickets it creates |
| `chat_backfill_minutes` | 60 | | how far back a first chat-intake pass reads |
| `chat_pending_passes` | 14 | | passes to wait for an author's answer before dropping an ambiguous ask |
| `discovery.ignore` | `[]` | | tool families or server names discovery must skip (agnostic front door) |
| `discovery.answers` | `{}` | | answers to past bootstrap questions, so rediscover does not ask again |
| `pending_questions` | `[]` | | bootstrap or run questions that could not be asked; shown on the dashboard, cleared when answered via `config` |
| `refine.mode` | `"auto"` | | `auto`: interview when a blocking thinness check fails; `always`: interview every new brief or loaded ticket; `off`: never interview (deferred behaviour only). See `ticket-refiner` |
| `refine.max_rounds` | 5 | yes | questions per refine interview on one ticket |
| `refine.epic_rounds` | 6 | yes | questions shared across one container's thin children in `epic-intake` |

`chat_channels[]` entries are either a channel id string or
`{channel, auto, kind: channel|dm}`.

`<front door> config` prints the effective config with defaults filled in
and the source of each value (default, file, learned on <date>).
`<front door> config <free text>` edits one key from a sentence
("default project VE", "gates spec,merge", "turn mutation off") and shows
the diff before writing.
