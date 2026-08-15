#!/usr/bin/env bash
# Build stats.json on a GitHub Actions runner.
#
# This is the CI twin of life/tools/publish-stats.sh. It exists because
# the local script cannot run here: it walks ~/Projects and counts every
# repo that is Barret's, which on a runner is an empty directory. The
# counting rules and the honesty rules are deliberately identical; only
# the discovery of repos differs.
#
#   local : "every repo in ~/Projects whose origin is bw9009/* or that
#            has no remote at all"
#   CI    : the explicit REPOS list below
#
# THAT IS A REAL DIFFERENCE. A new repo starts counting itself the
# moment it lands in ~/Projects locally; here it counts only once it is
# added to REPOS and to the checkout steps in stats.yml. If a number
# looks low after starting a project, this list is the first place to
# look.
#
# Tests: only re-run when the measured code actually changed. stats.json
# carries "lifeSha"; if it still matches, the previous pass/fail figures
# are reused and NOT marked stale, because an unchanged suite over
# unchanged code has not gone stale. If we genuinely could not measure,
# testsStale goes true - same rule as the local script: never publish a
# zero from a broken toolchain, and never publish "zero failing" when
# the truth is unknown.
set -u

SITE="${SITE:-$PWD}"
REPOS_DIR="${REPOS_DIR:-$SITE/_repos}"
OUT="$SITE/stats.json"
REPOS="life lifeos-site envelope-print"

commits=0
code=0
testfiles=0
repos=0
started=""
counted=""

for name in $REPOS; do
  d="$REPOS_DIR/$name"
  [ -d "$d/.git" ] || { echo "MISSING checkout: $name" >&2; continue; }
  repos=$((repos + 1))
  counted="$counted $name"

  c=$(git -C "$d" rev-list --count HEAD 2>/dev/null || echo 0)
  commits=$((commits + c))

  # Dart only - counting yaml and shell would inflate the number with
  # things nobody means by "lines of code".
  l=$(git -C "$d" ls-files '*.dart' 2>/dev/null | sed "s|^|$d/|" | xargs wc -l 2>/dev/null \
        | tail -1 | awk '{print $1}')
  [ -z "$l" ] && l=0
  code=$((code + l))

  tf=$(git -C "$d" ls-files 'test/*.dart' 2>/dev/null | wc -l | tr -d ' ')
  testfiles=$((testfiles + tf))

  s=$(git -C "$d" log --reverse --format=%as 2>/dev/null | head -1)
  if [ -n "$s" ]; then
    if [ -z "$started" ] || [ "$s" \< "$started" ]; then started="$s"; fi
  fi
done

# --- tests -----------------------------------------------------------
prev_pass=0; prev_fail=0
if [ -f "$OUT" ]; then
  prev_pass=$(grep -oE '"tests": *[0-9]+'        "$OUT" | grep -oE '[0-9]+' | head -1 || echo 0)
  prev_fail=$(grep -oE '"testsFailing": *[0-9]+' "$OUT" | grep -oE '[0-9]+' | head -1 || echo 0)
fi
[ -z "$prev_pass" ] && prev_pass=0
[ -z "$prev_fail" ] && prev_fail=0

pass=0
fail=0
stale=false

if [ "${RUN_TESTS:-0}" = "1" ]; then
  FLUTTER="$(command -v flutter 2>/dev/null || true)"
  if [ -n "$FLUTTER" ]; then
    for name in $REPOS; do
      d="$REPOS_DIR/$name"
      [ -f "$d/pubspec.yaml" ] || continue
      [ -d "$d/test" ] || continue
      (cd "$d" && "$FLUTTER" pub get >/dev/null 2>&1) || true
      # Progress uses carriage returns and the LAST lines are warning
      # text, so take the last real progress line: "MM:SS +1054 -184:"
      out=$(cd "$d" && "$FLUTTER" test 2>/dev/null \
            | tr '\r' '\n' \
            | grep -aE '^[0-9]+:[0-9]+ +\+[0-9]+' \
            | tail -1 || true)
      p=$(printf '%s' "$out" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+')
      f=$(printf '%s' "$out" | grep -oE ' -[0-9]+' | tail -1 | tr -d ' -')
      [ -n "$p" ] && pass=$((pass + p))
      [ -n "$f" ] && fail=$((fail + f))
    done
  fi
  if [ "$pass" -eq 0 ]; then
    # Could not measure. Carry the old numbers AND say so.
    pass=$prev_pass; fail=$prev_fail; stale=true
    echo "WARNING: test run produced nothing, reusing last known counts" >&2
  fi
else
  # Code did not change: the previous figures still describe it.
  pass=$prev_pass; fail=$prev_fail; stale=false
fi

[ -z "$started" ] && started="2026-07-31"
LIFE_SHA="${LIFE_SHA:-unknown}"

cat > "$OUT" <<JSON
{
  "commits": $commits,
  "lines": $code,
  "tests": $pass,
  "testsFailing": $fail,
  "testsStale": $stale,
  "testFiles": $testfiles,
  "repos": $repos,
  "started": "$started",
  "lifeSha": "$LIFE_SHA",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

echo "counted repos:$counted"
cat "$OUT"
