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

# TEST LOGS GO OUTSIDE THE REPO. They used to be written into $SITE,
# which left the working tree dirty - and the push-retry in stats.yml
# rebases, which git refuses to do with unstaged changes. So the retry
# that exists precisely for a push race could never survive one:
#   "cannot pull with rebase: You have unstaged changes"
#   "rebase failed; leaving master alone"
# The job did all its work and then threw it away, every time.
LOG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
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
      # --machine, because the human output is not a contract.
      #
      # The evidence for this: a forced CI run spent 5m13s in the test
      # step, wrote NOTHING to stderr, and still parsed nothing. So the
      # suite ran fine and only the scraping failed - the progress lines
      # ("MM:SS +1054 -184:") are a terminal convenience that CI does not
      # get, even though they appear locally when piped.
      #
      # --machine emits one JSON event per line, which is a documented
      # format rather than something that changes with the renderer.
      raw="$LOG_DIR/test-stdout-$name.log"
      (cd "$d" && "$FLUTTER" test --machine >"$raw" 2>>"$LOG_DIR/test-stderr.log") \
        || true

      counts=$(python3 - "$raw" <<'PY'
import json, sys
passed = failed = 0
with open(sys.argv[1], errors='replace') as fh:
    for line in fh:
        line = line.strip()
        if not line.startswith('{'):
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get('type') != 'testDone' or e.get('hidden'):
            continue
        if e.get('result') == 'success':
            passed += 1
        else:
            failed += 1
print(passed, failed)
PY
)
      p=$(printf '%s' "$counts" | awk '{print $1}')
      f=$(printf '%s' "$counts" | awk '{print $2}')
      echo "-- $name: $(wc -l < "$raw" | tr -d ' ') lines of machine output," \
           "passed=${p:-?} failed=${f:-?}" >&2
      [ "${p:-0}" -eq 0 ] && p=""
      [ -n "$p" ] && pass=$((pass + p))
      [ -n "$f" ] && fail=$((fail + f))
    done
  fi
  if [ "$pass" -eq 0 ]; then
    # Could not measure. Carry the old numbers AND say so.
    pass=$prev_pass; fail=$prev_fail; stale=true
    echo "WARNING: test run produced nothing, reusing last known counts" >&2
    echo "---- stderr ----" >&2
    cat "$LOG_DIR/test-stderr.log" >&2 2>/dev/null || echo "(no stderr file)" >&2
    for name in $REPOS; do
      raw="$LOG_DIR/test-stdout-$name.log"
      [ -f "$raw" ] || continue
      echo "---- first 25 lines of $name stdout ----" >&2
      head -25 "$raw" >&2
    done
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
