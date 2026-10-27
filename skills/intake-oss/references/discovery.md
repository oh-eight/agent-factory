# Discovery

Discovery writes `$FACTORY_HOME/profile.md`: one tool per capability, found
on this machine, with its auth state. It runs on the first `/intake-oss`,
on `config rediscover`, on `config ignore <name>`, and for a single
capability when a tool call fails with an unknown-tool error. It is read-only
apart from the profile and config it writes. Model: sonnet when spawned;
inline in harnesses without `Agent`.

This file is the one place in the engine that names tool families. It has
to, because it looks for them. Nothing else in the engine may quote a name
from these tables.

## 1. MCP tools

Two sources, merged:

- The tool names visible to the model in this session. In Claude Code they
  look like `mcp__<server>__<tool>`; the part before the last `__` is the
  server and sets `mcp_prefix` in the profile's `## Harness` section. In
  other harnesses names may be bare; then `mcp_prefix` is empty.
- `claude mcp list` when the CLI is on PATH. It prints a header line
  ("Checking MCP server health…") and then one line per server:
  `<server>: <command> - ✔ Connected` or `✘ Failed to connect`. Only
  `Connected` servers count. A server named `plugin:<plugin>:<name>` is
  addressed as `mcp__plugin_<plugin>_<name>__` in tool names.

Match every tool name against the family table. A server that exposes tools
from several families (an aggregator) contributes to each family separately;
the family is decided by the tool name, not the server.

| Family | Tool name patterns | Capabilities served | Auth probe (read-only) |
|---|---|---|---|
| jira | `jira_*`, `*Jira*` | tracker; sources for `*.atlassian.net/browse` | `jira_get_cloud_id`, `*atlassianUserInfo`, or `jira_search` with a tiny JQL |
| linear | `linear_*` | tracker; sources for `linear.app` | `linear_get_viewer`, `*viewer*` |
| github | `pull_request_read`, `create_pull_request`, `list_issues`, `issue_read`, `search_issues`, `search_code`, `get_me`, `github_*` | tracker (issues), pr, code (search), ci (workflow runs when a `*workflow*` or `*run*` tool exists) | `get_me` |
| gitlab | `gitlab_*`, `*merge_request*` | tracker, pr, ci | `*current_user*` |
| slack | `slack_*` | chat; sources for `*.slack.com/archives` | `whoami`, `*user_profile*` |
| discord | `discord_*` | chat; sources for `discord.com/channels` | `*me*` |
| notion | `notion_*` | sources for `notion.so`; knowledge | any `search` call with an empty query |
| confluence | `confluence_*`, `*Confluence*` | sources for `*.atlassian.net/wiki`; knowledge | `*atlassianUserInfo` |
| google docs | `gws_*`, `google_*`, `*docs*`, `*drive*` | sources for `docs.google.com`, `drive.google.com` | none; auth known on first fetch |
| grafana | `grafana_*`, `obs*`, `*prometheus*`, `*metrics_query*` | obs | a labels or datasource listing |
| datadog | `datadog_*`, `dd_*` | obs | `*validate*` or a metrics listing |
| sentry | `sentry_*` | obs (error counts), incidents (issues) | `*organizations*` listing |
| pagerduty | `pagerduty_*`, `pd_*`, `rootly_*`, `opsgenie_*` | incidents | `*current_user*` |
| buildkite | `bk_*`, `buildkite_*` | ci | `bk_list_builds` with a limit of 1 |
| circleci | `circleci_*` | ci | `*me*` |
| argocd | `argocd_*`, `argo_*`, `release_*deploy*`, `*live_status*` | deploy | an applications listing |
| sourcegraph | `sg_*`, `sourcegraph_*` | code | `sg_list_repos` with a limit of 1 |
| knowledge search | `*handbook*`, `glean_*`, `*knowledge*` | knowledge | any search with a one-word query |
| design system | `*design_system*`, `*components_list*`, `*tokens_data*` | design | the components listing |
| dispatcher | `create_thread` + `create_session` + `get_session_status` | dispatch | `list_threads` |

Run the probe once per family found. A probe that returns normally sets
`auth: ok`; an auth error sets `auth: missing`; any other error or no probe
sets `auth: unknown`. Never run a probe that writes.

## 2. CLIs on PATH

```bash
for c in gh glab jira linear slack kubectl aws gcloud docker bk src circleci argocd rg claude; do
  command -v "$c" >/dev/null 2>&1 && echo "present $c" || echo "absent $c"
done
```

Read-only auth probes, only for CLIs that are present:

| CLI | Probe | Capabilities served |
|---|---|---|
| `gh` | `gh auth status` (exit 0 → ok) | pr, tracker (issues, when chosen), ci (`gh run list/view --log-failed`), code (`gh search code`), sources for `github.com` |
| `glab` | `glab auth status` | pr, tracker (issues, when chosen), ci (`glab ci`), sources for `gitlab.com` |
| `jira` | `jira me` | tracker |
| `linear` | `linear --help` only (no auth probe known) → `auth: unknown` | tracker |
| `slack` | `slack auth list` | chat |
| `bk` | `bk api /user` | ci |
| `src` | `src login` prints the current user without writing | code |
| `argocd` | `argocd account get-user-info` | deploy |
| `kubectl`, `aws`, `gcloud`, `docker` | none; recorded under `## Harness` as `tools_present:` for the cartographer | none directly |
| `rg` | none | code fallback (always `cli:rg` when present) |

## 3. Repository signals

Only when the current directory is inside a git repository:

| Signal | Sets |
|---|---|
| `git remote get-url origin` host is `github.com` | pr candidate `cli:gh`; tracker candidate "repository issues via gh" |
| host is `gitlab.com` or the path has `/-/` | pr candidate `cli:glab`; tracker candidate "repository issues via glab" |
| other host | pr: none unless an MCP family covers it; gap |
| `.github/workflows/` | ci candidate `cli:gh run` |
| `.gitlab-ci.yml` | ci candidate `cli:glab ci` |
| `.buildkite/` | ci needs the buildkite family (MCP or `bk`); else gap "CI config present, no tool" |
| `.circleci/` | ci needs the circleci family; else the same gap |
| manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle*`, `Makefile`) | noted in `## Harness` as `manifests:`; the cartographer derives commands later |
| `.storybook/` or a Storybook URL in the README | design candidate `builtin:storybook <url>` |

## 4. Writing the profile

Follow `pipeline/references/profile-schema.md` exactly: every capability
section present, `tool:` in one of `mcp:<tool>`, `cli:<command template>`,
`skill:<name>`, `builtin:<name>`, `none`; `auth:` where a probe exists;
`ops:` lines where the default is not obvious; `notes:` with what the
engine needs to know (key syntax, how children attach, transition names,
label names); `hosts:` under `## sources`; a `## Gaps` list with one line per
`none` saying what the factory does instead (from the degradation column in
`capabilities.md`).

Fixed choices the agnostic profile always makes:

- `sources` always ends with `"*": builtin:WebFetch`.
- `code` is `cli:rg` plus any code-search family found.
- `pr.body` is `builtin:pr-template`; `pr.connect` is `none` unless a
  dispatcher family exposes a PR-claim tool; `pr.comment_prefix` is empty;
  `pr.branch_prefix` is `config.branch_prefix` or `<git user.name slug>/`.
- `dispatch` is `builtin:worktree+Agent` when the harness has `Agent` and
  git is present, else the dispatcher family, else `none`.
- `voice` is `builtin:prose`.
- `tracker` is never `none`: the fallback is `file` (see `file-tracker.md`).
- `ci.flake_patterns` points at `build-nurse/references/flake-patterns.md`
  (generic) unless a later lesson adds a per-repo file under `_repos/`.

Write to `profile.md.tmp`, then `mv`. Keep the previous profile as
`profile.prev.md` so `config rediscover` can print a diff.

## 5. Precedence between candidates

For each capability, in order:

1. Drop anything in `config.discovery.ignore`. An ignore entry matches a
   family name, or any MCP server name or tool prefix that contains it as a
   substring (`hub` drops `plugin:hub-tools:hub` and `mcp__hub__`).
2. `tracker` only: a project-keyed family (keys like `ABC-123`) always
   outranks the repository host's issues (`gh issue`, `glab issue`),
   whatever their auth states. Repository issues are a tracker candidate
   only when no project-keyed family is found, or the user chose them. The
   file tracker is the last resort and is always offered.
3. Drop `auth: missing` when another candidate exists. `unknown` (probe not
   run or not available) stays a candidate.
4. Among what remains, prefer MCP over CLI (structured results, no parsing).
5. Two remaining candidates for `tracker` (two project-keyed families) or
   for `chat` → a gap that changes behaviour: ask, once, in the bootstrap
   question. Record the answer in `config.discovery.answers` so rediscover
   does not ask again. With no way to ask, take the MCP one and record the
   question in `config.json.pending_questions[]`.
6. For every other capability with two candidates, take the first by the
   rules above and list the other in `notes:` as `also:`.

A server visible to the model counts even when `claude mcp list` does not
show it (plugins and hubs are often omitted there). When tools come from
several servers, `mcp_prefix:` lists one `server: prefix` pair per line
and a `default:`; each `mcp:` tool resolves against the server whose tool
list names it.

## 6. The ignore list

`config.discovery.ignore` holds family names from the table above, or MCP
server names. `config ignore <name>` appends and rediscovers. An ignored
family contributes no candidate to any capability, so ignoring the only
tracker family found makes discovery fall back to repository issues or the
file tracker and list the gaps.

## 7. Re-discovery triggers

- `config rediscover` or `config ignore`.
- A capability call fails with an unknown-tool error: rediscover that
  capability only, update the section, append to `## Gaps` if it is now
  `none`, print the change.
- `profile.md` is older than 30 days: the dashboard shows a one-line hint;
  nothing runs automatically.
- A run stamped with a profile name that does not match `profile.md`'s
  `# Profile:` line keeps using the stamped behaviour until it finishes.

## Example: a devbox with one aggregating MCP server

Facts found: the model sees tools named `mcp__hub__jira_get_issue`,
`mcp__hub__jira_search`, `mcp__hub__jira_create`, `mcp__hub__slack_mcp_slack_send_message`,
`mcp__hub__whoami`, `mcp__hub__bk_get_build_status_by_url`,
`mcp__hub__bk_retry_failed_jobs`, `mcp__hub__sg_keyword_search`,
`mcp__hub__grafana_query_prometheus`, `mcp__hub__pull_request_read`,
`mcp__hub__confluence_get_page`, `mcp__hub__argocd_get_application`,
`mcp__hub__rootly_list_incidents`, among others. `claude mcp list` prints
`hub: hub mcp serve - ✔ Connected`. On PATH: `gh` (authenticated), `kubectl`,
`aws`, `docker`, `rg`; absent: `glab`, `jira`, `linear`, `slack`, `bk`.
The current repository's remote is on `github.com` and has
`.buildkite/`.

Only one authenticated tracker candidate (the jira family), a chat candidate
exists, so the bootstrap question has two parts: chat notifications yes/no,
unattended merge yes/no.

```markdown
# Profile: discovered
generated: 2026-10-21T02:10:00Z  by: /intake-oss  harness: claude-code

## Harness
mcp_prefix: mcp__hub__
agent: yes
skill: yes
loop: yes
tools_present: gh kubectl aws docker rg

## tracker
tool: mcp:jira_get_issue
auth: ok
ops:
  search: mcp:jira_search
  create: mcp:jira_create
  update: mcp:jira_update
  comment: mcp:jira_add_comment
  transition: mcp:jira_transition_issue (names via mcp:jira_get_transitions)
  link: mcp:jira_link_issues
  children: mcp:jira_search with `parent = {key}`
  hierarchy_level: issuetype.hierarchyLevel from mcp:jira_get_issue
  types: mcp:jira_mcp_getJiraProjectIssueTypesMetadata
notes: |
  Key syntax [A-Z][A-Z0-9]+-\d+. Children attach through the parent field.
  Transition names are read per project at run time; do not assume them.
  Repository issues via gh were also authenticated; not chosen (also: cli:gh issue).

## sources
tool: mixed
hosts:
  "*.atlassian.net/browse": mcp:jira_get_issue
  "*.atlassian.net/wiki": mcp:confluence_get_page
  "*.slack.com/archives": mcp:slack_read_thread_raw
  "github.com": cli:gh (issue view, pr view, api)
  "*": builtin:WebFetch

## chat
tool: mcp:slack_mcp_slack_send_message
self: from mcp:whoami at first use
reply_prefix: ""

## code
tool: mcp:sg_keyword_search + cli:rg

## pr
tool: cli:gh
connect: none
comment_prefix: ""
branch_prefix: ""
body: builtin:pr-template

## ci
tool: mcp:bk_get_build_status_by_url
auth: unknown
ops:
  failed_jobs: mcp:bk_get_build_status_by_url
  logs: mcp:bk_get_logs_by_url
  retry: mcp:bk_retry_failed_jobs
root_cause: none
flake_patterns: <resolved path of the installed build-nurse skill>/references/flake-patterns.md   # readlink -f on the skill dir the harness loaded
notes: |
  Repository has .buildkite/. GitHub checks are still read through pr.checks.

## obs
tool: mcp:grafana_query_prometheus
auth: unknown
ops:
  logs_count: mcp:grafana_query_loki
  alerts_firing: none
  explore_link: none

## deploy
tool: mcp:argocd_get_application

## incidents
tool: mcp:rootly_list_incidents

## dispatch
tool: builtin:worktree+Agent

## knowledge
tool: mcp:glean_search

## design
tool: none

## voice
tool: builtin:prose

## Gaps
- ci.root_cause: no structured tool; the nurse reads the failing log tail
- obs.alerts_firing, obs.explore_link: no tool; the sentinel checks metrics and log counts only
- design: none; the UX reviewer skips design-system checks
- pr.connect: none; PRs are not attached to a dispatcher
```

With `config ignore hub` the same machine yields `tracker: cli:gh issue`
(auth ok) or, if the user picks it, `tracker: file`; `chat: none`;
`ci: cli:gh run` only if `.github/workflows/` exists, else `none` with a
gap; `code: cli:rg`; `obs`, `deploy`, `incidents`, `knowledge`: `none`,
each listed under `## Gaps` with the stage it disables.
