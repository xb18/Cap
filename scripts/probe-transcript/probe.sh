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

header() {
  read -r _ CY CL < <(loc header "Clean" 1000 $W 0 300) || return 1
  PLUS_X=$((CL - 110)) DOWNLOAD_X=$((CL - 78)) HEADER_Y=$CY
}

drive_light() {
  launch light || return
  ffmpeg -loglevel error -y -f x11grab -framerate 15 -video_size ${W}x${H} -i "$DISPLAY" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$out/transcript-captions-light.mp4" &
  rec=$!
  pause 2
  shot light-01-transcript
  read -r WX WY _ < <(loc word "mishurd." 900 $W 100 700) || { result light_word missing; return; }
  dclick "$WX" "$WY"; pause 1.2
  shot light-02-field-open
  xdotool type --delay 110 "misheard."; pause 0.8
  shot light-03-typed
  key Tab; pause 1.5
  shot light-04-tab-next-word
  key Escape; pause 1
  grep -q "transcript word edited" "$out/app-light.log" && result light_word_edit ok || result light_word_edit fail
  click "$WX" "$WY"; pause 1
  key space; pause 3; key space; pause 1
  shot light-05-caption-in-preview
  key ctrl+z; pause 1.5
  shot light-06-undo
  key ctrl+shift+z; pause 1.5
  shot light-07-redo

  read -r TX TY _ < <(loc things "things." 900 $W 100 700) && { click "$TX" "$TY"; pause 1; }
  header && { click "$PLUS_X" "$HEADER_Y"; pause 2; shot light-08-added-at-playhead; }
  grep -q '"add-caption"\|reason="add-caption"\|add-caption' "$out/app-light.log" && result light_add_playhead ok || result light_add_playhead fail
  read -r _ LY _ < <(loc lane "Captions" 0 250 500 $H)
  read -r _ _ X5 < <(loc ruler5 "0:05" 0 $W 500 $H)
  read -r _ _ X10 < <(loc ruler10 "0:10" 0 $W 500 $H)
  if [[ -n ${LY:-} && -n ${X5:-} && -n ${X10:-} ]]; then
    LX=$(python3 -c "print(round($X5 + (12.9 - 5) * ($X10 - $X5) / 5))")
    click "$LX" "$LY"; pause 2
    shot light-09-lane-click
    result light_lane_click "x=$LX,y=$LY"
  else
    result light_lane_click missing
  fi

  read -r TABX TABY _ < <(loc tab "Transcript" 1000 $W 0 100) && { click "$TABX" "$TABY"; pause 1; }
  header && {
    click "$DOWNLOAD_X" "$HEADER_Y"; pause 1.2
    shot light-10-download-menu
    read -r SX SY _ < <(loc srt "SubRip" 900 $W 0 600) && { click "$SX" "$SY"; pause 2.5; shot light-11-saved; }
    click "$DOWNLOAD_X" "$HEADER_Y"; pause 1.2
    read -r VX VY _ < <(loc vtt "WebVTT" 900 $W 0 600) && { click "$VX" "$VY"; pause 2.5; }
  }
  pause 1
  kill -INT $rec; wait $rec; rec=""
}

drive_dark() {
  launch dark || return
  shot dark-01-transcript
  read -r WX WY _ < <(loc word "mishurd." 900 $W 100 700) && {
    dclick "$WX" "$WY"; pause 1.2
    shot dark-02-field-open
    key Escape; pause 1
  }
  read -r TX TY _ < <(loc things "things." 900 $W 100 700) && { click "$TX" "$TY"; pause 1; }
  header && {
    click "$PLUS_X" "$HEADER_Y"; pause 2
    shot dark-03-added-at-playhead
    read -r TABX TABY _ < <(loc tab "Transcript" 1000 $W 0 100) && { click "$TABX" "$TABY"; pause 1; }
    header && { click "$DOWNLOAD_X" "$HEADER_Y"; pause 1.2; shot dark-04-download-menu; key Escape; }
  }
}

drive_light
drive_dark
rm -f "$out/_loc.png"
for f in "$out"/saved/*; do
  [[ -f $f ]] || continue
  echo "===== $(basename "$f")"
  cat "$f"
  result "saved_$(basename "$f" | sed 's/.*\.//')" ok
done
cat "$out/portal.log"
grep -E "transcript word edited|caption download|captions saved|saving captions failed|add-caption|panicked" "$out"/app-*.log | cut -c1-240
cat "$out/result.txt"
