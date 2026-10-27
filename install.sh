#!/usr/bin/env bash
# install.sh: link every skills/<name> in this repo into the skill
# directories of the harnesses present on this machine.
#
#   ./install.sh                      link into every harness whose home dir exists
#   ./install.sh --target claude      only ~/.claude/skills (also: cursor, codex, all)
#   ./install.sh --check              list link status, change nothing
#   ./install.sh --uninstall          remove only links that point into this repo
#
# A target directory is skipped when another tool owns it: when the
# directory is itself a symlink, or when it contains symlinks that resolve
# into a path matching one of the colon-separated substrings in
# FACTORY_FOREIGN_MARKERS (unset by default). A real directory that would
# collide with a link is moved aside to <name>.pre-factory. Idempotent;
# never execs anything.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_DIR="$REPO_DIR/skills"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

# Portable "resolve every symlink" without relying on GNU readlink -f.
resolve() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null && return 0
  fi
  if readlink -f / >/dev/null 2>&1; then
    readlink -f "$p" 2>/dev/null && return 0
  fi
  local target dir
  local i=0
  while [ -L "$p" ] && [ $i -lt 40 ]; do
    target="$(readlink "$p")"
    case "$target" in
      /*) p="$target" ;;
      *)  p="$(dirname "$p")/$target" ;;
    esac
    i=$((i + 1))
  done
  dir="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s\n' "$p"; return 0; }
  printf '%s/%s\n' "$dir" "$(basename "$p")"
}

target_dir() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude/skills" ;;
    cursor) printf '%s\n' "$HOME/.cursor/skills" ;;
    codex)  printf '%s\n' "$HOME/.agents/skills" ;;
    *) echo "unknown target: $1" >&2; exit 2 ;;
  esac
}

harness_home() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude" ;;
    cursor) printf '%s\n' "$HOME/.cursor" ;;
    codex)  printf '%s\n' "$HOME/.agents" ;;
  esac
}

# Prints a reason and returns 0 when the directory is owned by another tool.
managed_reason() {
  local dir="$1" entry raw abs marker markers
  if [ -L "$dir" ]; then
    printf 'directory is itself a symlink to %s\n' "$(readlink "$dir")"
    return 0
  fi
  [ -d "$dir" ] || return 1
  markers="${FACTORY_FOREIGN_MARKERS:-}"
  [ -n "$markers" ] || return 1
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [ -L "$entry" ] || continue
    raw="$(readlink "$entry")"
    abs="$(resolve "$entry")"
    IFS=: read -ra marker_list <<< "$markers"
    for marker in "${marker_list[@]}"; do
      [ -n "$marker" ] || continue
      case "$raw$abs" in
        *"$marker"*)
          printf 'contains links managed by another tool (%s -> %s)\n' "$(basename "$entry")" "$raw"
          return 0 ;;
      esac
    done
  done
  return 1
}

in_repo() {
  case "$1" in
    "$REPO_DIR"/*|"$REPO_DIR") return 0 ;;
    *) return 1 ;;
  esac
}

skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    basename "$d"
  done
}

install_into() {
  local t="$1" dir reason name src dest existing backup
  dir="$(target_dir "$t")"
  if reason="$(managed_reason "$dir")"; then
    echo "skip   $dir: $reason"
    return 0
  fi
  mkdir -p "$dir"
  echo "target $dir"
  for name in $(skills); do
    src="$SKILLS_DIR/$name"
    dest="$dir/$name"
    if [ -L "$dest" ]; then
      existing="$(resolve "$dest")"
      if [ "$existing" = "$src" ]; then
        echo "  ok     $name"
      elif in_repo "$existing"; then
        ln -sfn "$src" "$dest"
        echo "  relink $name"
      else
        echo "  skip   $name: symlink to $(readlink "$dest") belongs to something else"
      fi
      continue
    fi
    if [ -d "$dest" ]; then
      backup="$dest.pre-factory"
      [ -e "$backup" ] && backup="$backup.$(date +%Y%m%d%H%M%S)"
      mv "$dest" "$backup"
      echo "  moved  $name -> $(basename "$backup")"
    elif [ -e "$dest" ]; then
      echo "  skip   $name: a file is in the way"
      continue
    fi
    ln -s "$src" "$dest"
    echo "  link   $name"
  done
}

uninstall_from() {
  local t="$1" dir name dest backup
  dir="$(target_dir "$t")"
  [ -d "$dir" ] || return 0
  echo "target $dir"
  for name in $(skills); do
    dest="$dir/$name"
    [ -L "$dest" ] || continue
    if in_repo "$(resolve "$dest")"; then
      rm "$dest"
      echo "  unlink $name"
      backup="$dest.pre-factory"
      if [ -d "$backup" ] && [ ! -e "$dest" ]; then
        mv "$backup" "$dest"
        echo "  restore $name from $(basename "$backup")"
      fi
    fi
  done
}

check_target() {
  local t="$1" dir reason name dest
  dir="$(target_dir "$t")"
  if [ ! -d "$dir" ] && [ ! -L "$dir" ]; then
    echo "$t  $dir  (absent)"
    return 0
  fi
  if reason="$(managed_reason "$dir")"; then
    echo "$t  $dir  (skipped: $reason)"
    return 0
  fi
  echo "$t  $dir"
  for name in $(skills); do
    dest="$dir/$name"
    if [ -L "$dest" ]; then
      if in_repo "$(resolve "$dest")"; then
        echo "  linked   $name"
      else
        echo "  foreign  $name -> $(readlink "$dest")"
      fi
    elif [ -d "$dest" ]; then
      echo "  realdir  $name"
    elif [ -e "$dest" ]; then
      echo "  file     $name"
    else
      echo "  missing  $name"
    fi
  done
}

mode=install
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || { usage; exit 2; }; target="$2"; shift 2 ;;
    --target=*) target="${1#--target=}"; shift ;;
    --uninstall) mode=uninstall; shift ;;
    --check) mode=check; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ -d "$SKILLS_DIR" ] || { echo "no skills/ directory next to $0" >&2; exit 1; }

targets=()
case "$target" in
  "")
    for t in claude cursor codex; do
      [ -d "$(harness_home "$t")" ] && targets+=("$t")
    done
    [ ${#targets[@]} -gt 0 ] || { echo "no harness home directory found (~/.claude, ~/.cursor, ~/.agents); pass --target"; exit 1; }
    ;;
  all) targets=(claude cursor codex) ;;
  claude|cursor|codex) targets=("$target") ;;
  *) echo "unknown target: $target (claude | cursor | codex | all)" >&2; exit 2 ;;
esac

for t in "${targets[@]}"; do
  case "$mode" in
    install) install_into "$t" ;;
    uninstall) uninstall_from "$t" ;;
    check) check_target "$t" ;;
  esac
done
