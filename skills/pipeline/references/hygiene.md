# Tracker hygiene

The ticket is the team's window into the run. Keep it current without
flooding it.

## Comments

One short comment per stage transition, through `tracker.comment`, after
`voice.polish(text, durable)`. One to three lines, links included, no
narration:

| Transition | Comment |
|---|---|
| → `prepare` (round 1) | Branch name, repository, link to the brief's sources if they were not already on the ticket |
| → `verify` | Round N: X claims built, tests added, link to the PR branch |
| verify FINDINGS | Round N: Y findings (Z deferred to follow-ups KEY-…), back to prepare |
| → `pr` | PR link, draft or ready |
| → `gated` | What is waiting and for whom |
| → `escalated` | One paragraph from `escalation.md`: the reason and the one question |
| → `merge` | Merged sha |
| → `done` | Sentinel verdict and the learner's lesson count |

Non-code modes comment their deliverable (`research.md`, `measurement.md`,
`recommendation.md`) in full, since the comment is the deliverable.

## Transitions

Use `tracker.transition(key, state)` with engine states; the profile maps
them to vendor names:

| Stage | State |
|---|---|
| `prepare` (first time) | `in_progress` |
| `pr` | `in_review` |
| `merge` or non-code deliverable posted | `done` |

If the profile has no mapping for a state, comment instead and record a
gap. Never move a ticket backwards.

## Labels

Only `factory` and `epic-intake` add or remove labels, with one exception:
`chat-intake` and a front door's `batch` path may add `factory-auto` at
create time to the tickets they create, because the dispatcher they hand off
to selects by that label. Engine label names
(the profile may rename them in `notes:`):

| Label | Meaning |
|---|---|
| `factory-auto` | eligible for dispatch |
| `factory-running` | claimed by a dispatcher |
| `factory-blocked` | escalated; needs a human |
| `factory-gated` | waits on a human decision by design (decision, rollout) |
| `factory-mode:<mode>` | overrides the work type |
| `factory-followup` | created by triage from a deferred finding |

## Child and follow-up tickets

Created tickets link back to their origin: parent for epic children and
decomposer splits, `relates` for triage follow-ups. The origin comment names
the new keys.
