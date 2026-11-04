#!/usr/bin/env bash
# Check one status.json against references/state-schema.md: the required
# fields (key, mode, stage, round), the type of every field it names, and
# the mode and stage enums.
#
#   check-status.sh <status.json>
#
# Prints one "<field>: <problem>" line per problem, in the order of the
# schema example; a value is printed JSON-encoded with every code point
# outside printable ASCII as \uXXXX. Exit 0: clean (no output). Exit 1:
# problems. Exit 2: bad usage, a file it cannot read, or a program that
# failed; stdout is then empty, and stderr names the file by its base name
# only. Extra keys are allowed; cross-field rules are not checked. Writes no
# files.
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
for t in jq od awk tr; do
  command -v "$t" >/dev/null 2>&1 || die "missing program: $t"
done

# jq decodes invalid UTF-8 as U+FFFD, so the bytes are checked first, one
# decimal byte per od word, against the RFC 3629 table: no C0, C1 or F5-FF
# lead, no overlong form, no surrogate, nothing above U+10FFFF, no sequence
# cut short. Not iconv: macOS iconv accepts 5- and 6-byte forms.
utf8="$(LC_ALL=C od -An -v -tu1 < "$f" | LC_ALL=C awk '
  {
    for (i = 1; i <= NF; i++) {
      b = $i + 0
      if (need) {
        if (b < lo || b > hi) bad = 1
        need--; lo = 128; hi = 191
      } else if (b >= 128) {
        lo = 128; hi = 191
        if (b >= 194 && b <= 223) need = 1
        else if (b >= 224 && b <= 239) { need = 2; if (b == 224) lo = 160; if (b == 237) hi = 159 }
        else if (b >= 240 && b <= 244) { need = 3; if (b == 240) lo = 144; if (b == 244) hi = 143 }
        else bad = 1
      }
    }
  }
  END { print (bad || need) ? 0 : 1 }
')" || die "cannot check $name (od failed)"
case "$utf8" in 0|1) ;; *) die "cannot check $name (od failed)" ;; esac

# jq also parses what RFC 8259 rejects (NaN, Infinity, 01, .5, 1., +1):
# outside strings, every token has to be a JSON literal or number. One pass,
# with no regex over long text (awk's is slow there): tr turns NUL into \001
# (just as bad outside a string; awk drops NUL) and every separator into a
# newline; awk then reads one record per '"'. In a string, a record that ends
# in an odd run of backslashes escapes the quote; outside, the text splits
# into tokens, and a string counts as "" in the token around it.
strict="$(LC_ALL=C tr '\000\011\015\040\054\072\133\135\173\175' '\001\n\n\n\n\n\n\n\n\n' < "$f" \
  | LC_ALL=C awk -v RS='"' -v FS='\\' '
  function ok(t) {
    return t == "" || t == "\"\"" || t == "true" || t == "false" || t == "null" ||
      t ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$/
  }
  instr {
    k = 0
    for (i = NF; i > 1 && $i == ""; i--) k++
    if (k % 2 == 0) { instr = 0; cur = cur "\"\"" }
    next
  }
  {
    n = split($0, a, "\n")
    if (n > 0) {
      a[1] = cur a[1]
      for (i = 1; i < n; i++) if (!ok(a[i])) bad = 1
      cur = a[n]
    }
    instr = 1
  }
  END { if (!ok(cur)) bad = 1; print bad ? 0 : 1 }
')" || die "cannot check $name (awk failed)"
case "$strict" in 0|1) ;; *) die "cannot check $name (awk failed)" ;; esac

# The last line is an end marker, so output from a jq that did not run the
# program is never taken for a clean file.
end="check-status.sh:end"
out="$(jq -R -s -r --arg end "$end" --arg utf8 "$utf8" --arg strict "$strict" '
  def hex4: [(. / 4096 | floor) % 16, (. / 256 | floor) % 16, (. / 16 | floor) % 16, . % 16]
    | map("0123456789abcdef"[.:. + 1]) | add;
  def asc: tojson | explode
    | map(if . >= 32 and . < 127 then [.] | implode
          elif . < 65536 then "\\u" + hex4
          else (. - 65536) as $c
            | "\\u" + ((55296 + ($c / 1024 | floor)) | hex4)
              + "\\u" + ((56320 + ($c % 1024)) | hex4) end)
    | add;
  def num_or_type: if type == "number" then tostring else type end;
  def want(f; w; ok; got): if ok then empty else "\(f): want \(w), got \(got)" end;
  def str(f): want(f; "string"; type == "string"; type);
  def strnull(f): want(f; "string or null"; type == "string" or type == "null"; type);
  def obj(f): want(f; "object"; type == "object"; type);
  def arr(f): want(f; "array"; type == "array"; type);
  def enum(f; vals): . as $v
    | if type != "string" then str(f)
      elif any(vals[]; . == $v) then empty
      else "\(f): unknown value \(asc)" end;
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
  (if $utf8 == "1" and $strict == "1" then (try [fromjson] catch null) else null end) as $w
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
