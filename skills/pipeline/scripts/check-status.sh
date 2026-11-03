#!/usr/bin/env bash
# Check one status.json against references/state-schema.md: the required
# fields (key, mode, stage, round), the type of every field it names, and
# the mode and stage enums.
#
#   check-status.sh <status.json>
#
# Prints one "<field>: <problem>" line per problem, in the order of the
# schema example. Exit 0: clean (no output). Exit 1: problems. Exit 2: bad
# usage, a file it cannot read, or a program that failed; stdout is then
# empty, and stderr names the file by its base name only. Extra keys are
# allowed; cross-field rules are not checked. Writes no files.
set -uo pipefail

usage() {
  echo "check-status.sh: usage: check-status.sh <status.json>" >&2
  exit 2
}
die() {
  echo "check-status.sh: $*" >&2
  exit 2
}

[ $# = 1 ] || usage
case "$1" in
  -*|'') usage ;;
esac
f="$1"
name="${f##*/}"
{ [ -f "$f" ] && [ -r "$f" ]; } || die "not a readable file: $name"
command -v jq >/dev/null 2>&1 || die "missing program: jq"

# The last line is an end marker, so output from a jq that did not run the
# program is never taken for a clean file.
end="check-status.sh:end"
out="$(jq -R -s -r --arg end "$end" '
  def num_or_type: if type == "number" then tostring else type end;
  def want(f; w; ok; got): if ok then empty else "\(f): want \(w), got \(got)" end;
  def str(f): want(f; "string"; type == "string"; type);
  def strnull(f): want(f; "string or null"; type == "string" or type == "null"; type);
  def obj(f): want(f; "object"; type == "object"; type);
  def arr(f): want(f; "array"; type == "array"; type);
  def enum(f; vals): . as $v
    | if type != "string" then str(f)
      elif any(vals[]; . == $v) then empty
      else "\(f): unknown value \(tojson)" end;
  def runstages: ["intake", "prepare", "spec", "verify", "pr", "nurse", "gated", "merge",
    "sentinel", "incident", "learn", "done", "escalated", "stopped"];
  def epicstages: ["intake", "gated", "planned", "dispatching", "done", "stopped"];
  def modes: ["code", "research", "measure", "decision", "rollout", "closeout", "epic"];
  def rule(k; $mode): if k == "key" then
      want(k; "non-empty string"; type == "string" and . != ""; if . == "" then "\"\"" else type end)
    elif k == "mode" then enum(k; modes)
    elif k == "stage" then enum(k; if $mode == "epic" then epicstages else runstages end)
    elif k == "round" then
      want(k; "integer >= 1"; type == "number" and . == floor and . >= 1; num_or_type)
    elif k == "profile" or k == "harness" then str(k)
    elif k == "epic" or k == "pending_gate" then strnull(k)
    elif k == "children" or k == "gates" or k == "instructions" or k == "gaps" or k == "history" then arr(k)
    else obj(k) end;
  def required: ["key", "mode", "stage", "round"];
  def order: ["key", "profile", "mode", "epic", "stage", "round", "harness", "repo",
    "branch", "ticket", "children", "pr", "nurse", "review", "sanity", "sentinel",
    "gates", "pending_gate", "overrides", "budget", "instructions", "gaps", "lock", "costs",
    "history"];
  def costs:
    (if has("spawns") then .spawns
       | want("costs.spawns"; "integer >= 0"; type == "number" and . == floor and . >= 0; num_or_type)
     else empty end),
    (if has("by_stage") then .by_stage | obj("costs.by_stage") else empty end),
    (if has("wall_minutes") then .wall_minutes
       | want("costs.wall_minutes"; "number >= 0"; type == "number" and . >= 0; num_or_type)
     else empty end);
  (try [fromjson] catch null) as $w
  | (if $w == null or ($w | length) != 1 then "(root): not valid JSON"
     elif ($w[0] | type) != "object" then "(root): want object, got \($w[0] | type)"
     else
       $w[0] as $s
       | order[] as $k
       | if ($s | has($k)) then
           ($s[$k] | rule($k; $s.mode)),
           (if $k == "costs" and ($s.costs | type) == "object" then $s.costs | costs else empty end)
         elif any(required[]; . == $k) then "\($k): missing"
         else empty end
     end),
    $end
' 2>/dev/null < "$f")" || die "cannot check $name (jq failed)"

case "$out" in
  "$end") exit 0 ;;
  *"
$end") printf '%s\n' "${out%"
$end"}"; exit 1 ;;
  *) die "unexpected jq output" ;;
esac
