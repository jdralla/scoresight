#!/bin/bash
# ScoreSight (USC fork) - build watcher, v1.0
# Leave this running in a Terminal window. Whenever a file named
# "run-request" appears in ~/ScoreSight-build, it downloads the latest
# build_and_test_mac.sh from the branch and runs it, writing the output to
# ~/ScoreSight-build/agent/run-<n>.log and the exit status to run-<n>.done.
# Optional: the first line of run-request is passed as environment settings
# (e.g. "SKIP_BUILD=1 RUNS=5"). Stop it with Ctrl-C.
BRANCH="${BRANCH:-usc/startup-shutdown-fixes}"
WORK="$HOME/ScoreSight-build"; OUT="$WORK/agent"
URL="https://raw.githubusercontent.com/jdralla/scoresight/refs/heads/$BRANCH/scripts/usc/build_and_test_mac.sh"
mkdir -p "$OUT"
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
echo "Watching $WORK/run-request (branch $BRANCH). Leave this window open; Ctrl-C to stop."
n=$(ls "$OUT"/run-*.done 2>/dev/null | wc -l | tr -d ' ')
while true; do
  date > "$OUT/heartbeat"
  if [ -f "$WORK/run-request" ]; then
    envline="$(head -1 "$WORK/run-request" | tr -cd 'A-Za-z0-9_=/. -')"
    rm -f "$WORK/run-request"
    n=$((n+1)); log="$OUT/run-$n.log"
    echo "[$(date +%H:%M:%S)] run $n starting ${envline:+($envline)}"
    if curl -fsSL "$URL?t=$(date +%s)" -o "$OUT/build_and_test_mac.sh"; then
      # shellcheck disable=SC2086
      env $envline caffeinate -i bash "$OUT/build_and_test_mac.sh" >"$log" 2>&1
      rc=$?
    else
      echo "could not download the script" >"$log"; rc=97
    fi
    echo "$rc" > "$OUT/run-$n.done"
    echo "[$(date +%H:%M:%S)] run $n finished (exit $rc)"
  fi
  sleep 5
done
