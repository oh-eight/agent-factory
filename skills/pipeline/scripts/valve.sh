#!/usr/bin/env bash
# Evaluate the pipeline valve for one run directory. The conditions, their
# order and the reason lines are documented in references/governor.md
# ("Valve").
#
#   valve.sh <run-dir>
#
# <run-dir> is the directory that holds the run's status.json. Budgets come
# from status.json.budget, then from budget in the config.json in the run
# directory's parent (FACTORY_HOME is not read), then the governor defaults.
# Prints exactly one line: "ok" (exit 0) or "tripped: <reason>" (exit 3).
# Exit 2: bad usage, an input it cannot read or evaluate, or a program that
# failed; stdout is then empty. Exit 1 is not used. Missing optional files
# (verification/, build/, nurse/, costs.json, run.log, config.json) trip
# nothing. Writes no files.
set -uo pipefail

usage() {
  echo "valve.sh: usage: valve.sh <run-dir>" >&2
  exit 2
}
die() {
  echo "valve.sh: $*" >&2
  exit 2
}

[ $# = 1 ] || usage
case "$1" in
  -*|'') usage ;;
esac
dir="$1"
[ -d "$dir" ] || die "not a directory: $dir"

for t in jq awk sort sed; do
  command -v "$t" >/dev/null 2>&1 || die "missing program: $t"
done
export LC_ALL=C

# present FILE: 0 when FILE is a readable regular file, 1 when it does not
# exist; anything else (a directory, a dangling link, no read permission)
# cannot be evaluated and stops with 2.
present() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then return 1; fi
  if [ -f "$1" ] && [ -r "$1" ]; then return 0; fi
  die "not a readable file: $1"
}
# presentdir DIR: the same for a directory that has to be listed.
presentdir() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then return 1; fi
  if [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ]; then return 0; fi
  die "not a readable directory: $1"
}
isnum() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

present "$dir/status.json" || die "no status.json in $dir"

# The parent of the path as given (a symlinked run dir gets the link's
# parent, not the target's): cd resolves ".." logically.
parent="$(unset CDPATH; cd -- "$dir/.." 2>/dev/null && pwd)" || die "cannot resolve the parent of $dir"
[ -n "$parent" ] || die "cannot resolve the parent of $dir"
cfg="$parent/config.json"

# JSON inputs. An absent file is passed as /dev/null with its flag off.
hascf=0; hasld=0; hascs=0
cf=/dev/null; ld=/dev/null; cs=/dev/null
if present "$cfg"; then hascf=1; cf="$cfg"; fi
if presentdir "$dir/verification" && present "$dir/verification/ledger.json"; then
  hasld=1; ld="$dir/verification/ledger.json"
fi
if present "$dir/costs.json"; then hascs=1; cs="$dir/costs.json"; fi

# One jq pass validates every JSON input and prints one tab-separated
# "facts" line: round, round-1, the four limits, spawns, costs.json
# entries, wall minutes (floored) and the ledger fingerprint that repeats
# (JSON-encoded, "-" for none). Any input it cannot evaluate prints an
# "error" line instead.
facts="$(jq -n -r --slurpfile st "$dir/status.json" --slurpfile cf "$cf" \
  --slurpfile ld "$ld" --slurpfile cs "$cs" \
  --arg hascf "$hascf" --arg hasld "$hasld" --arg hascs "$hascs" '
  def isint: type == "number" and . == floor;
  def posint: isint and . >= 1;
  def one(name): if length == 1 and (.[0] | type) == "object" then .[0]
    else error(name + ": not one JSON object") end;
  def bobj(name): if . == null then {} elif type == "object" then .
    else error(name + ": budget is not an object or null") end;
  def chk(name): . as $b
    | reduce ("max_rounds", "max_inner_passes", "max_agent_spawns", "max_wall_minutes") as $k
        ($b; if .[$k] != null and ((.[$k] | posint) | not)
             then error(name + ": budget." + $k + " is not an integer >= 1") else . end);
  try (
    ($st | one("status.json")) as $s
    | $s.round as $r
    | if ($r | posint) then . else error("status.json: round is not an integer >= 1") end
    | $s.costs as $c
    | if $c == null or ($c | type) == "object" then . else error("status.json: costs is not an object") end
    | $c.spawns as $sp
    | if $sp == null or ($sp | isint and . >= 0) then . else error("status.json: costs.spawns is not an integer >= 0") end
    | $c.wall_minutes as $wm
    | if $wm == null or ($wm | type == "number" and . >= 0) then . else error("status.json: costs.wall_minutes is not a number >= 0") end
    | ($s.budget | bobj("status.json") | chk("status.json")) as $sb
    | (if $hascf == "1" then (if ($cf | length) == 0 then {} else ($cf | one("config.json")) end) else {} end) as $cfg
    | ($cfg.budget | bobj("config.json") | chk("config.json")) as $cb
    | (if $hasld == "1" then ($ld | one("ledger.json")) else {} end) as $l
    | ($l | to_entries | map(
        if (.value | type) != "object" then error("ledger.json: an entry is not an object")
        elif (.value.rounds | type) != "array" or ((.value.rounds | all(.[]; isint)) | not)
          then error("ledger.json: rounds is not a list of integers")
        elif (.value.status | type) != "string" then error("ledger.json: status is not a string")
        else . end
        | select(.value.status == "open"
                 and (.value.rounds | any(.[]; . == $r - 1))
                 and (.value.rounds | any(.[]; . == $r)))
        | .key) | sort | if length > 0 then (.[0] | tojson) else "-" end) as $lfp
    | (if $hascs == "1" then
         (if ($cs | length) == 1 and ($cs[0] | type) == "array" then $cs[0] else $cs end)
         | if all(.[]; type == "object") then length else error("costs.json: an entry is not an object") end
       else 0 end) as $n
    | ["facts"]
      + ([$r, $r - 1,
          ($sb.max_rounds // $cb.max_rounds // 5),
          ($sb.max_inner_passes // $cb.max_inner_passes // 3),
          ($sb.max_agent_spawns // $cb.max_agent_spawns // 60),
          ($sb.max_wall_minutes // $cb.max_wall_minutes // 240),
          ($sp // 0), $n, ($wm // 0)] | map(floor | tostring))
      + [$lfp]
    | join("\t")
  ) catch ("error\t" + tostring)
')" || die "cannot evaluate the JSON inputs (jq failed)"

case "$facts" in
  "error	"*) die "${facts#error	}" ;;
  "facts	"*) ;;
  *) die "unexpected jq output" ;;
esac
# Split on tabs only; the ledger fingerprint is JSON-encoded, so it holds no
# tab or newline.
oldifs="$IFS"
IFS='	'
set -f
# shellcheck disable=SC2086
set -- $facts
set +f
IFS="$oldifs"
[ $# = 11 ] || die "unexpected jq output"
r="$2"; p="$3"; mr="$4"; mi="$5"; ms="$6"; mw="$7"; sp="$8"; sc="$9"; wm="${10}"; lfp="${11}"
for v in "$r" "$p" "$mr" "$mi" "$ms" "$mw" "$sp" "$sc" "$wm"; do
  isnum "$v" || die "a number in the JSON inputs is out of range"
done
case "$lfp" in
  -|\"*\") ;;
  *) die "unexpected jq output" ;;
esac

shopt -s nullglob

# Repeat in nurse/ci-findings.md: a "### F-" line in a "# CI findings
# round R" section with R in [N-1, N] whose repeat-of is set and not none.
# The byte-order-first fingerprint wins; for the same fingerprint, the
# higher round. A repeat with no fingerprint cannot be evaluated.
cfp=""; cr=""
if presentdir "$dir/nurse" && present "$dir/nurse/ci-findings.md"; then
  hit="$(awk -v n="$r" '
    function val(k,   i) {
      for (i = 2; i < NF; i++) if ($i == k && $(i + 1) !~ /:$/) return $(i + 1)
      return ""
    }
    /^# CI findings round [0-9]+/ { s = $5 + 0; insec = 1; next }
    /^### F-/ {
      if (!insec || (s != n && s != n - 1)) next
      rep = val("repeat-of:")
      if (rep == "" || tolower(rep) == "none") next
      fp = val("fingerprint:")
      if (fp == "") { bad = 1; exit }
      print fp "\t" s
    }
    END { if (bad) exit 4 }' "$dir/nurse/ci-findings.md" \
    | sort -t '	' -k1,1 -k2,2nr | sed -n 1p)" || die "cannot evaluate nurse/ci-findings.md"
  if [ -n "$hit" ]; then
    fp="${hit%	*}"
    cr="${hit##*	}"
    isnum "$cr" || die "cannot evaluate nurse/ci-findings.md"
    cfp="$(jq -n -r --arg f "$fp" '$f | tojson')" || die "cannot encode a fingerprint (jq failed)"
    case "$cfp" in
      \"*\") ;;
      *) die "unexpected jq output" ;;
    esac
  fi
fi

# First "verdict:" line of a round file, trailing whitespace dropped.
verdict() {
  awk '/^verdict:/ { v = $0; sub(/^verdict:[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$1"
}
vp=""; vn=""
if presentdir "$dir/verification"; then
  if [ "$p" -ge 1 ] && present "$dir/verification/round-$p.md"; then
    vp="$(verdict "$dir/verification/round-$p.md")" || die "cannot read verification/round-$p.md"
  fi
  if present "$dir/verification/round-$r.md"; then
    vn="$(verdict "$dir/verification/round-$r.md")" || die "cannot read verification/round-$r.md"
  fi
fi
blk=0; inv=0
[ "$vp" = BLOCKED ] && [ "$vn" = BLOCKED ] && blk=1
[ "$vp" = INVALID ] && [ "$vn" = INVALID ] && inv=1

# Round N's builder reports, the fix passes and the summary outcome.
dec=0; ip=0; ob=0; ck=""
rd="$dir/build/round-$r"
if presentdir "$dir/build" && presentdir "$rd"; then
  for f in "$rd/builder.md" "$rd"/builder-fix-*.md; do
    present "$f" || continue
    # A non-blank line under "## Decisions needed" (up to the next heading
    # of level 1 or 2) that is not "none" is a decision.
    d="$(awk '
      /^## / { ins = ($0 ~ /^## Decisions needed[ \t\r]*$/); next }
      /^# / { ins = 0; next }
      ins {
        l = $0; gsub(/^[ \t]+|[ \t\r]+$/, "", l)
        if (l == "") next
        t = tolower(l); sub(/^[-*][ \t]*/, "", t)
        if (t ~ /^\(?none\)?\.?$/) next
        found = 1; exit
      }
      END { if (found) print "yes" }' "$f")" || die "cannot read $f"
    [ "$d" = yes ] && dec=1
  done
  for f in "$rd"/fix-pass-*.md; do
    [ -f "$f" ] && ip=$((ip + 1))
  done
  if present "$rd/summary.md"; then
    o="$(awk '/^outcome:/ { v = $0; sub(/^outcome:[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$rd/summary.md")" \
      || die "cannot read build/round-$r/summary.md"
    [ "$o" = blocked ] && ob=1
  fi
fi

# Wall minutes from the last run.log checkpoint line; a wall= value that is
# not a number counts for nothing.
if present "$dir/run.log"; then
  ck="$(awk '$2 == "checkpoint" {
      w = ""
      for (i = 3; i <= NF; i++) if ($i ~ /^wall=[0-9]+\//) { w = $i; sub(/^wall=/, "", w); sub(/\/.*/, "", w) }
      last = w
    }
    END { print last }' "$dir/run.log")" || die "cannot read run.log"
  [ -z "$ck" ] || isnum "$ck" || die "cannot read run.log"
fi

# The first condition that holds, in the documented order.
line="$(VALVE_LFP="$lfp" VALVE_CFP="$cfp" awk -v r="$r" -v p="$p" -v mr="$mr" -v mi="$mi" \
  -v ms="$ms" -v mw="$mw" -v sp="$sp" -v sc="$sc" -v wm="$wm" -v ck="$ck" -v cr="$cr" \
  -v blk="$blk" -v inv="$inv" -v dec="$dec" -v ip="$ip" -v ob="$ob" 'BEGIN {
    if (r + 0 >= mr + 0) { print "tripped: max_rounds round=" r " limit=" mr; exit }
    if (ENVIRON["VALVE_LFP"] != "-") {
      print "tripped: repeat fingerprint=" ENVIRON["VALVE_LFP"] " source=ledger rounds=" p "," r; exit
    }
    if (ENVIRON["VALVE_CFP"] != "") {
      print "tripped: repeat fingerprint=" ENVIRON["VALVE_CFP"] " source=ci-findings round=" cr; exit
    }
    if (blk == 1) { print "tripped: blocked twice rounds=" p "," r; exit }
    if (inv == 1) { print "tripped: invalid twice rounds=" p "," r; exit }
    if (dec == 1) { print "tripped: decision needed round=" r; exit }
    su = sp + 0; if (sc + 0 > su) su = sc + 0
    if (su > ms + 0) { print "tripped: budget max_agent_spawns used=" su " limit=" ms; exit }
    wu = wm + 0; if (ck != "" && ck + 0 > wu) wu = ck + 0
    if (wu > mw + 0) { print "tripped: budget max_wall_minutes used=" wu " limit=" mw; exit }
    if (ip + 0 > mi + 0 || (ip + 0 == mi + 0 && ob == 1)) {
      print "tripped: budget max_inner_passes used=" ip " limit=" mi; exit
    }
    print "ok"
  }')" || die "cannot evaluate the conditions (awk failed)"

case "$line" in
  ok) echo ok; exit 0 ;;
  "tripped: "*) printf '%s\n' "$line"; exit 3 ;;
  *) die "unexpected result" ;;
esac
