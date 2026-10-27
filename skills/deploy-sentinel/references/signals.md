# Signals

The signals the sentinel compares on every pass, in a generic shape. Angle
brackets are placeholders the sentinel fills from the profile's `## obs`
notes, cartography, and the `## Learned` table below (see `## Profile
overrides`). Queries are written in a PromQL-like metrics form and a plain
log-query form; the profile's `obs` tool decides the real dialect, and the
sentinel rewrites the shape, not the meaning.

## Placeholders

| Placeholder | Meaning | Typical default |
|---|---|---|
| `<service>` | the deployed unit the change belongs to | from the profile notes or cartography `## Repo` deploy section |
| `<service_label>` | metric label that names the service | `service` |
| `<requests_total>` | request counter | `http_requests_total` or the RPC equivalent |
| `<status_label>` | label carrying the response status | `status` or `code` |
| `<error_match>` | regex for failed responses | `"5.."` or `"INTERNAL\|UNAVAILABLE\|UNKNOWN"` |
| `<latency_bucket>` | histogram bucket series for request latency | `http_request_duration_seconds_bucket` |
| `<log_service_field>` | log field naming the service | `service` or `app` |
| `<log_level_field>` | log field with the severity | `level` |

## Signal table

| Signal | Detects | Default query shape | Threshold (vs baseline) | Consecutive passes |
|---|---|---|---|---|
| `error_ratio` | failed share of requests after the deploy | `sum(rate(<requests_total>{<service_label>="<service>", <status_label>=~<error_match>}[5m])) / sum(rate(<requests_total>{<service_label>="<service>"}[5m]))` | mean over the pass window > 2x baseline mean **and** > 0.5 percentage points above it | 1 |
| `p95_latency` | tail latency regression | `histogram_quantile(0.95, sum by (le) (rate(<latency_bucket>{<service_label>="<service>"}[5m])))` | mean over the pass window > 1.5x baseline mean | 2 |
| `error_logs` | new error paths that metrics may not count | `<log_service_field>="<service>" AND <log_level_field> IN (error, fatal)` counted over the window | count per 15 minutes > 2x baseline **and** at least 10 lines more | 2 |
| `alerts` | alert rules for the service going into firing | `obs.alerts_firing(<service>)` | any alert firing now that was not firing at `live_at` | 1 |
| `incidents` | humans already treating this as an incident | `incidents.list(<service>, since=<live_at>)` | any incident open now or opened after `live_at` whose service, title or description names `<service>` | 1 |

Rules that apply to the whole table:

- **Baseline** is the same query for `[live_at - 60m, live_at]`: the mean at
  5-minute steps for ratios and quantiles; the hourly count divided by four
  for logs; the list of firing alert names; the list of open incident ids.
- **Pass window** is `[max(now - 15m, live_at), now]`. A pass shorter than 5
  minutes after `live_at` records values but trips nothing; the first
  comparison is at least 5 minutes after live.
- **Consecutive passes** means the signal was marked over (`!`) in the
  previous `sentinel/log.md` line as well. A pass where the signal is
  unavailable resets the streak.
- **Low traffic.** When the baseline hour has fewer than 100 requests,
  `error_ratio` trips only when the absolute rise is more than 1 percentage
  point and the window has at least 5 failed requests; `p95_latency` needs 3
  consecutive passes.
- **Unavailable** (`null` from the tool) is reported, never counted as
  healthy. A signal unavailable for the entire window blocks `HEALTHY` and
  becomes a gap.
- **Alert matching.** An alert is "tied to the service" when its labels
  carry `<service_label>="<service>"`, or its name or annotations contain the
  service name. Alerts already firing at `live_at` are pre-existing and are
  listed in the baseline, not counted.

## Profile overrides

The profile's `## obs` `notes:` may replace any placeholder, any whole query,
or any threshold for a service, and may add signals (a saturation metric, a
queue depth, a business counter). Cartography (`_repos/<owner>-<repo>.md`,
`## Repo` deploy section) may name the service, the dashboard, and the
metric family the team watches. Resolution order, most specific first:

1. `## Learned` row for this service and signal (below).
2. Profile `## obs` notes naming this service.
3. Profile `## obs` notes that apply to every service (label names, dialect).
4. Cartography deploy section.
5. The defaults in this file.

Added signals follow the same row shape (detects, query, threshold,
consecutive passes) and appear in the log line and the anomaly table like
the defaults. A profile cannot remove `alerts` or `incidents` when the
capability exists; it can only change how the service is matched.

## Learned

Appended by `learner` when a lesson about a sentinel threshold repeats
(`_lessons/INDEX.md` count 2 or more). One row per change; newer rows for
the same service and signal win. The sentinel reads this table; it never
writes it.

| date | service | signal | threshold | reason | run |
|---|---|---|---|---|---|
