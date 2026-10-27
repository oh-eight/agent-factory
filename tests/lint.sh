#!/usr/bin/env bash
# Static lints for this repo. Prints one line per failure, exits 1 on any.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

fail=0
bad() { echo "FAIL: $*"; fail=1; }

# Report every line of a grep result as its own failure.
report_lines() {
  local label="$1" out="$2" line
  [ -n "$out" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] && bad "$label: $line"
  done <<< "$out"
}

# 1. Every skill directory has a SKILL.md whose name matches the directory,
#    under 500 lines.
for d in skills/*/; do
  dir="${d%/}"
  base="$(basename "$dir")"
  if [ ! -f "$dir/SKILL.md" ]; then
    bad "$dir: no SKILL.md"
    continue
  fi
  name="$(sed -n 's/^name: *//p' "$dir/SKILL.md" | head -1)"
  [ "$name" = "$base" ] || bad "$dir/SKILL.md: frontmatter name '$name' does not match directory '$base'"
  lines="$(wc -l < "$dir/SKILL.md")"
  [ "$lines" -lt 500 ] || bad "$dir/SKILL.md: $lines lines (limit 500)"
done

# 2. No hardcoded home directories. The pattern is split so this file does
#    not match itself.
home_pat='/home/co''der|/Use''rs/'
report_lines "hardcoded home path" "$(grep -rnE "$home_pat" skills/ install.sh README.md tests/ 2>/dev/null)"

# 3. No secrets. Token-shaped strings and key=value assignments only, so
#    prose about "design tokens" or "auth" does not trip it.
secret_pat='xox[bp]-[A-Za-z0-9-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{15,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|(token|password|secret|api[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{12,}'
report_lines "possible secret" "$(grep -rnEi "$secret_pat" skills/ install.sh README.md 2>/dev/null)"

# 4. The engine is vendor-free. Only the discovery and classifier references
#    of intake-oss may name tool families, because they have to look for them.
vendor_pat='canva|otter|jira|buildkite|slack|forge|easel|obshub|epilog'
vendor_hits="$(grep -rniE "$vendor_pat" skills/ 2>/dev/null \
  | grep -vE '^skills/intake-oss/references/(discovery|classifier)\.md:')"
report_lines "vendor word in engine" "$vendor_hits"

# 5. Every subagent role file carries the header rule sentence.
rule='If any input is missing, stop and say which'
for f in skills/*/agents/*.md; do
  [ -f "$f" ] || continue
  if ! tr -s '[:space:]' ' ' < "$f" | grep -qF "$rule"; then
    bad "$f: missing the header rule sentence \"$rule\""
  fi
done

# 6. Shell scripts parse.
for s in install.sh tests/*.sh; do
  [ -f "$s" ] || continue
  bash -n "$s" 2>/dev/null || bad "$s: does not parse"
done

if [ "$fail" -eq 0 ]; then
  echo "lint ok"
  exit 0
fi
exit 1
