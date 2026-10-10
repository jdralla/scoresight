#!/bin/bash
# ScoreSight (USC fork) - macOS build + launch/quit timing test, v1.0
#
# What it does:
#   1. Checks this Mac (Apple Silicon, Xcode command line tools, Homebrew)
#   2. Installs build dependencies (Homebrew: python@3.11, tesseract, pkg-config)
#   3. Downloads the jdralla/scoresight branch and builds scoresight.app (arm64, onedir)
#   4. Downloads the official v0.1.0 arm64 release as a baseline
#   5. Launches and quits each app several times and times:
#        - launch -> HTTP API (http://127.0.0.1:18099/json) answering
#        - quit request -> all processes gone
#      No camera or Wirecast is needed for this test.
#
# Usage:
#   bash build_and_test_mac.sh                 # build + test (default branch below)
#   BRANCH=fix/http-server-shutdown bash build_and_test_mac.sh
#   RUNS=5 bash build_and_test_mac.sh
#   SKIP_BUILD=1 bash build_and_test_mac.sh    # re-run the timing test only
#
# Everything goes into ~/ScoreSight-build. Your ScoreSight settings file is
# backed up before the test and restored afterwards.

set -u
VERSION="v1.0"
BRANCH="${BRANCH:-usc/startup-shutdown-fixes}"
REPO_URL="https://github.com/jdralla/scoresight.git"
BASELINE_URL="https://github.com/royshil/scoresight/releases/download/0.1.0/scoresight-macos-arm64-0.1.0.dmg"
RUNS="${RUNS:-3}"
WORK="$HOME/ScoreSight-build"
SRC="$WORK/src"
VENV="$WORK/venv"
LOGS="$WORK/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="$WORK/results-$STAMP.txt"
CSV="$WORK/results-$STAMP.csv"
SETTINGS_DIR="$HOME/Library/Application Support/scoresight"
SETTINGS="$SETTINGS_DIR/scoresight.json"
PORT=18099

mkdir -p "$WORK" "$LOGS"

say()  { printf '\n\033[1;31m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31mSTOPPED:\033[0m %s\n' "$*"; exit 1; }
now()  { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
port_up() { curl -s -o /dev/null -m 0.5 "http://127.0.0.1:$PORT/json"; }

echo "ScoreSight macOS build + timing test $VERSION  ($STAMP)"
echo "Branch: $BRANCH   Runs per test: $RUNS   Work folder: $WORK"

# ---------------------------------------------------------------- 1. checks
say "1/5 Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || die "This script must run on macOS."
[ "$(uname -m)" = "arm64" ] || die "This script expects an Apple Silicon Mac (arm64); got $(uname -m)."
info "macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"

if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1
  die "Apple's command line developer tools are needed. A window should have opened to install them - finish that install, then run this script again."
fi
info "Xcode command line tools: OK"

if ! command -v brew >/dev/null 2>&1; then
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew is needed. Install it by pasting the command from https://brew.sh into Terminal (it asks for your Mac password), then run this script again."
fi
info "Homebrew: $(brew --version | head -1)"

if port_up; then
  die "Something is already answering on port $PORT (is ScoreSight open?). Quit it and run again."
fi

# ---------------------------------------------------------------- 2-3. build
APP_NEW="$SRC/dist/scoresight.app"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  say "2/5 Installing build dependencies (Homebrew)"
  brew install python@3.11 tesseract pkg-config >"$LOGS/brew-$STAMP.log" 2>&1 \
    || die "brew install failed - see $LOGS/brew-$STAMP.log"
  PY="$(brew --prefix python@3.11)/bin/python3.11"
  [ -x "$PY" ] || die "python3.11 not found after install."
  info "Python: $($PY --version)   Tesseract: $(tesseract --version 2>&1 | head -1)"

  say "3/5 Downloading branch '$BRANCH' and building scoresight.app"
  if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q origin "$BRANCH" && git -C "$SRC" checkout -q -B "$BRANCH" FETCH_HEAD \
      || die "git update failed."
  else
    rm -rf "$SRC"
    git clone -q --branch "$BRANCH" "$REPO_URL" "$SRC" || die "git clone failed."
  fi
  COMMIT="$(git -C "$SRC" rev-parse --short HEAD)"
  info "Commit: $COMMIT"

  [ -d "$VENV" ] || "$PY" -m venv "$VENV" || die "could not create Python venv."
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  info "Installing Python packages (first run takes several minutes)..."
  (
    cd "$SRC" &&
    python -m pip install -q --upgrade pip &&
    python -m pip install -q --no-binary tesserocr tesserocr &&
    python -m pip install -q -r requirements.txt &&
    python -m pip install -q -r requirements-mac.txt
  ) >"$LOGS/pip-$STAMP.log" 2>&1 || die "pip install failed - see $LOGS/pip-$STAMP.log"

  printf 'LOCAL_RELEASE_TAG=usc-%s\nLOCAL_RELEASE_DATE=%s\n' "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SRC/.env"

  info "Running PyInstaller..."
  ( cd "$SRC" && SCORESIGHT_TARGET_ARCH=arm64 APPLE_APP_DEVELOPER_ID="" \
      pyinstaller --clean --noconfirm scoresight.spec -- --mac_osx ) >"$LOGS/pyinstaller-$STAMP.log" 2>&1 \
    || die "PyInstaller build failed - see $LOGS/pyinstaller-$STAMP.log"
  deactivate
  [ -d "$APP_NEW" ] || die "Build finished but $APP_NEW is missing."
  info "Built: $APP_NEW  ($(du -sh "$APP_NEW" | cut -f1), $(lipo -archs "$APP_NEW/Contents/MacOS/scoresight"))"
else
  say "2-3/5 Skipping build (SKIP_BUILD=1)"
  [ -d "$APP_NEW" ] || die "No previous build at $APP_NEW."
fi

# ---------------------------------------------------------------- 4. baseline
say "4/5 Getting the official v0.1.0 release as a baseline"
APP_OLD="$WORK/baseline/scoresight.app"
if [ ! -d "$APP_OLD" ]; then
  mkdir -p "$WORK/baseline"
  curl -fL# -o "$WORK/baseline/scoresight-0.1.0.dmg" "$BASELINE_URL" || die "baseline download failed."
  MNT="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$WORK/baseline/scoresight-0.1.0.dmg" >/dev/null \
    || die "could not open the baseline DMG."
  ditto "$MNT/scoresight.app" "$APP_OLD"
  hdiutil detach "$MNT" >/dev/null
fi
info "Baseline: $APP_OLD  ($(du -sh "$APP_OLD" | cut -f1), $(lipo -archs "$APP_OLD/Contents/MacOS/scoresight"))"

# ---------------------------------------------------------------- 5. timing
say "5/5 Timing launch and quit ($RUNS runs each). Please don't touch ScoreSight while this runs."
info "If macOS asks about network access or incoming connections, click Allow - the test continues either way."

BACKUP=""
if [ -f "$SETTINGS" ]; then
  BACKUP="$WORK/scoresight.json.backup-$STAMP"
  cp "$SETTINGS" "$BACKUP"
  info "Backed up your settings to $BACKUP"
fi
restore_settings() {
  if [ -n "$BACKUP" ]; then cp "$BACKUP" "$SETTINGS"; else rm -f "$SETTINGS"; fi
}
trap 'restore_settings' EXIT
mkdir -p "$SETTINGS_DIR"

pids_of() { pgrep -f "$1/Contents/MacOS/" ; }
mei_count() { ls -d "${TMPDIR:-/tmp}"/_MEI* 2>/dev/null | wc -l | tr -d ' '; }

echo "label,run,launch_to_http_s,quit_to_exit_s,quit_result,leftover_tmp_folders" > "$CSV"

run_one() {   # $1 label  $2 app path  $3 settings json  $4 run#
  local label="$1" app="$2" settings="$3" n="$4"
  printf '%s' "$settings" > "$SETTINGS"
  local mei_before t0 t_up t_q t_gone up_s quit_s result mei_after
  mei_before=$(mei_count)
  t0=$(now)
  open -n "$app" || { info "could not launch $app"; return; }
  up_s="timeout"
  for _ in $(seq 1 600); do            # up to 60 s
    if port_up; then t_up=$(now); up_s=$(echo "$t_up - $t0" | bc); break; fi
    sleep 0.1
  done
  sleep 2                               # let it settle like a real session
  t_q=$(now)
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 &
  result="clean"; quit_s="timeout"
  for _ in $(seq 1 300); do             # up to 30 s
    if [ -z "$(pids_of "$app")" ]; then t_gone=$(now); quit_s=$(echo "$t_gone - $t_q" | bc); break; fi
    sleep 0.1
  done
  if [ "$quit_s" = "timeout" ]; then
    result="HUNG (force-killed after 30 s)"
    pids_of "$app" | xargs kill -9 2>/dev/null
    sleep 1
  fi
  for _ in $(seq 1 50); do port_up || break; sleep 0.1; done
  mei_after=$(mei_count)
  printf '    %-28s run %d:  launch->HTTP %6ss   quit->exit %6ss   %s\n' "$label" "$n" "$up_s" "$quit_s" "$result"
  echo "$label,$n,$up_s,$quit_s,$result,$((mei_after - mei_before))" >> "$CSV"
  sleep 2
}

for n in $(seq 1 "$RUNS"); do run_one "v0.1.0 official"           "$APP_OLD" '{}' "$n"; done
for n in $(seq 1 "$RUNS"); do run_one "USC build"                 "$APP_NEW" '{}' "$n"; done
for n in $(seq 1 "$RUNS"); do run_one "USC build, NDI off"        "$APP_NEW" '{"enable_ndi": false}' "$n"; done

restore_settings; trap - EXIT

# ---------------------------------------------------------------- summary
{
  echo "ScoreSight macOS timing test $VERSION - $STAMP"
  echo "Mac: $(sysctl -n hw.model) / $(sysctl -n machdep.cpu.brand_string) / macOS $(sw_vers -productVersion)"
  echo "Branch: $BRANCH  Commit: $(git -C "$SRC" rev-parse --short HEAD 2>/dev/null)"
  echo
  awk -F, 'NR>1 {
      k=$1; n[k]++
      if ($3!="timeout") {u[k]+=$3; nu[k]++}
      if ($4!="timeout") {q[k]+=$4; nq[k]++} else hung[k]++
      if (!(k in order)) {order[k]=++c; names[c]=k}
    }
    END {
      printf "%-26s %18s %18s %8s\n", "Test", "avg launch->HTTP", "avg quit->exit", "hung"
      for (i=1;i<=c;i++){k=names[i]
        printf "%-26s %17ss %17ss %8d\n", k, (nu[k]?sprintf("%.2f",u[k]/nu[k]):"-"), (nq[k]?sprintf("%.2f",q[k]/nq[k]):"-"), hung[k]+0 }
    }' "$CSV"
  echo
  echo "Raw data: $CSV"
} | tee "$RESULTS"

say "Done. Results saved to $RESULTS"
