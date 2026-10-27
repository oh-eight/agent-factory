#!/usr/bin/env bash
# Creates the toy repository the factory is exercised against: a tiny Python
# CLI called sum with two passing tests and one deliberate gap (no handling
# of non-numeric arguments).
#
#   tests/toy-repo.sh                 create $HOME/tmp/pipeline-toy if missing
#   tests/toy-repo.sh <dir>           create at <dir>
#   tests/toy-repo.sh [<dir>] --reset delete and recreate
set -euo pipefail

reset=0
dir=""
for arg in "$@"; do
  case "$arg" in
    --reset) reset=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) dir="$arg" ;;
  esac
done
dir="${dir:-$HOME/tmp/pipeline-toy}"

if [ -e "$dir" ]; then
  if [ "$reset" -eq 1 ]; then
    rm -rf "$dir"
  else
    echo "exists: $dir (pass --reset to recreate)"
    exit 0
  fi
fi

mkdir -p "$dir"
cd "$dir"

cat > sum.py <<'EOF'
#!/usr/bin/env python3
"""sum: add the integer arguments and print the total."""
import sys


def add(values):
    return sum(int(v) for v in values)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    print(add(argv))
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF

cat > test_sum.py <<'EOF'
import pathlib
import subprocess
import sys

SUM = pathlib.Path(__file__).with_name("sum.py")


def run(*args):
    return subprocess.run(
        [sys.executable, str(SUM), *args], capture_output=True, text=True
    )


def test_adds_integers():
    result = run("2", "3", "4")
    assert result.returncode == 0
    assert result.stdout.strip() == "9"


def test_no_arguments_is_zero():
    result = run()
    assert result.returncode == 0
    assert result.stdout.strip() == "0"
EOF

cat > README.md <<'EOF'
# pipeline-toy

A one-file CLI used to exercise the factory end to end.

Run:

    python3 sum.py 1 2 3

Test:

    python3 -m pytest -q

`sum.py` adds its integer arguments and prints the total.
EOF

cat > .gitignore <<'EOF'
__pycache__/
.pytest_cache/
EOF

chmod +x sum.py

git init -q
git symbolic-ref HEAD refs/heads/main
git add -A
if git config user.email >/dev/null 2>&1 && git config user.name >/dev/null 2>&1; then
  git commit -q -m "Add sum CLI with two tests"
else
  git -c user.name="toy" -c user.email="toy@example.invalid" commit -q -m "Add sum CLI with two tests"
fi

echo "created: $dir"
echo "  run:  python3 sum.py 1 2 3"
echo "  test: python3 -m pytest -q"
