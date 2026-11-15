#!/usr/bin/env bash
# Throwaway media probe for the transcript word edit, add caption and caption
# download PRs: drives the real editor under Xvfb with xdotool, records it,
# and saves SRT and WebVTT through a stand-in file chooser portal.
# Usage: probe.sh <cap-gpui> <ffmpeg lib dir> <out-dir>
set -uo pipefail
if [[ -z ${PROBE_BUS:-} ]]; then
  exec env PROBE_BUS=1 dbus-run-session -- bash "$0" "$@"
fi
here=$(cd "$(dirname "$0")" && pwd)
bin=$1 libs=$2 out=$3
mkdir -p "$out"
: >"$out/result.txt"
result() { printf '%s=%s\n' "$1" "$2" | tee -a "$out/result.txt"; }
export LD_LIBRARY_PATH=$libs
unset WAYLAND_DISPLAY
export DISPLAY=:91 XDG_SESSION_TYPE=x11 W=1600 H=1000
Xvfb "$DISPLAY" -screen 0 ${W}x${H}x24 >/dev/null 2>&1 &
xvfb=$!
sleep 1
python3 "$here/portal.py" "$out/saved" >"$out/portal.log" 2>&1 &
portal=$!
sleep 1
app="" rec=""
trap 'kill $rec $app $portal $xvfb 2>/dev/null' EXIT

shot() { ffmpeg -loglevel error -y -f x11grab -video_size ${W}x${H} -i "$DISPLAY" -frames:v 1 "$out/$1.png"; }
loc() {
  local name=$1 text=$2; shift 2
  shot "_loc"
  python3 "$here/loc.py" "$out/_loc.png" "$text" "$@" || { echo "not found: $text" >&2; return 1; }
}
click() { xdotool mousemove "$1" "$2"; sleep 0.4; xdotool click "${3:-1}"; }
dclick() { xdotool mousemove "$1" "$2"; sleep 0.5; xdotool click --repeat 2 --delay 90 1; }
key() { xdotool key "$@"; }
pause() { sleep "${1:-1}"; }

launch() {
  local theme=$1
  [[ -n $app ]] && { kill $app 2>/dev/null; wait $app 2>/dev/null; sleep 1; }
  local project=$out/run-$theme/demo.cap profile=$out/run-$theme/profile
  mkdir -p "$profile"
  cp -R "$here/demo.cap" "$out/run-$theme/"
  printf '{"general_settings":{"theme":"%s","hasCompletedOnboarding":true,"hasCompletedStartup":true,"enableNotifications":false,"enableTelemetry":false,"recordingCountdown":0}}' "$theme" >"$profile/store"
  CAP_GPUI_APP_DATA_DIR=$profile CAP_GPUI_AUTO_EDITOR=$project CAP_GPUI_AUTO_TRANSCRIPT=open RUST_LOG=info \
    "$bin" >"$out/app-$theme.log" 2>&1 &
  app=$!
  for _ in $(seq 240); do grep -q "transcript opened" "$out/app-$theme.log" && break; sleep 0.5; done
  grep -q "transcript opened" "$out/app-$theme.log" || { result "${theme}_launch" fail; return 1; }
  local win
  win=$(xdotool search --name "Cap Editor" | tail -1)
  [[ -z $win ]] && win=$(xdotool search --onlyvisible --class "cap" | tail -1)
  result "${theme}_window" "${win:-none}"
  xdotool windowmove "$win" 0 0
  xdotool windowsize "$win" $W $H
  xdotool windowfocus "$win" 2>/dev/null
  sleep 3
  result "${theme}_launch" ok
}

# Positions read from the stills of run 43622807378 (1600x1000, window at 0,0).
PLUS_X=1409 DOWNLOAD_X=1441 HEADER_Y=119
SRT_X=1489 SRT_Y=153 VTT_X=1491 VTT_Y=177
TAB_X=1383 TAB_Y=74
LANE_Y=844 PLAYHEAD_Y=768
WORD_X=1265 WORD_Y=312 THINGS_X=1364 THINGS_Y=190

adds() { grep -c 'reason="add-caption"' "$out/app-$1.log"; }
word_pos() { loc word "mishurd." 900 $W 100 700 || echo "$WORD_X $WORD_Y 0"; }

add_and_lane() {
  local theme=$1 before
  click "$THINGS_X" "$THINGS_Y"; pause 1
  before=$(adds "$theme")
  click "$PLUS_X" "$HEADER_Y"; pause 2
  shot "$theme-08-added-at-playhead"
  [[ $(adds "$theme") -gt $before ]] && result "${theme}_add_playhead" ok || result "${theme}_add_playhead" fail
  shot "_gap"
  local gx
  gx=$(python3 "$here/gap.py" "$out/_gap.png" $LANE_Y $PLAYHEAD_Y) || { result "${theme}_lane_click" missing; return; }
  before=$(adds "$theme")
  click "$gx" "$LANE_Y"; pause 2
  shot "$theme-09-lane-click"
  [[ $(adds "$theme") -gt $before ]] && result "${theme}_lane_click" "ok x=$gx" || result "${theme}_lane_click" "fail x=$gx"
}

download() {
  local theme=$1
  click "$TAB_X" "$TAB_Y"; pause 1.2
  click "$DOWNLOAD_X" "$HEADER_Y"; pause 1.2
  shot "$theme-10-download-menu"
  [[ $theme == dark ]] && { key Escape; pause 0.5; return; }
  click "$SRT_X" "$SRT_Y"; pause 2.5
  shot "$theme-11-saved"
  click "$DOWNLOAD_X" "$HEADER_Y"; pause 1.2
  click "$VTT_X" "$VTT_Y"; pause 2.5
}

drive_light() {
  launch light || return
  ffmpeg -loglevel error -y -f x11grab -framerate 15 -video_size ${W}x${H} -i "$DISPLAY" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$out/transcript-captions-light.mp4" &
  rec=$!
  pause 2
  shot light-01-transcript
  read -r WX WY _ < <(word_pos)
  dclick "$WX" "$WY"; pause 1.2
  shot light-02-field-open
  xdotool type --delay 110 "misheard."; pause 0.8
  shot light-03-typed
  key Tab; pause 1.5
  shot light-04-tab-next-word
  key Escape; pause 1
  shot light-04b-escape
  grep -q "transcript word edited" "$out/app-light.log" && result light_word_edit ok || result light_word_edit fail
  click "$WX" "$WY"; pause 1
  key space; pause 3; key space; pause 1
  shot light-05-caption-in-preview
  key ctrl+z; pause 1.5
  shot light-06-undo
  key ctrl+shift+z; pause 1.5
  shot light-07-redo
  add_and_lane light
  download light
  pause 1
  kill -INT $rec; wait $rec; rec=""
}

drive_dark() {
  launch dark || return
  ffmpeg -loglevel error -y -f x11grab -framerate 15 -video_size ${W}x${H} -i "$DISPLAY" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$out/transcript-captions-dark.mp4" &
  rec=$!
  pause 2
  shot dark-01-transcript
  read -r WX WY _ < <(word_pos)
  dclick "$WX" "$WY"; pause 1.2
  shot dark-02-field-open
  xdotool type --delay 110 "misheard."; pause 0.8
  key Return; pause 1.2
  shot dark-03-word-fixed
  grep -q "transcript word edited" "$out/app-dark.log" && result dark_word_edit ok || result dark_word_edit fail
  add_and_lane dark
  download dark
  pause 1
  kill -INT $rec; wait $rec; rec=""
}

drive_light
drive_dark
rm -f "$out/_loc.png" "$out/_gap.png"
for f in "$out"/saved/*; do
  [[ -f $f ]] || continue
  echo "===== $(basename "$f")"
  cat "$f"
  result "saved_$(basename "$f" | sed 's/.*\.//')" ok
done
cat "$out/portal.log"
grep -E "transcript word edited|caption|subtitle|saved|add-caption|panicked|undo|redo" "$out"/app-*.log | cut -c1-240
cat "$out/result.txt"
