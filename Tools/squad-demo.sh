#!/bin/bash
# squad-demo.sh — set up the three-simulator live squad poll.
#
#   Tools/squad-demo.sh setup     boot 3 sims, build, install, launch (leader straight into curation)
#   Tools/squad-demo.sh relay     run the relay in the foreground (leave this terminal visible)
#   Tools/squad-demo.sh logs      stream the squad log from all three sims, prefixed per device
#   Tools/squad-demo.sh logs A    stream one device only (A = leader, B and C = joiners)
#   Tools/squad-demo.sh relaunch B    rebuild-free relaunch of one sim, to test rejoin-with-vote-intact
#
# The relay and the logs each want their own terminal. The room is inspectable from
# both sides at once: the relay prints what it received, the app prints what it sent
# and what it made of the answer.

set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE=aryaman.Wandr

# Rename these if your machine has different simulators — `xcrun simctl list devices available`.
A=82BD28EC-4A98-42BB-892D-2F0F5F58DAE8   # iPhone 17 Pro Max — the leader
B=5AA701AC-BB40-4373-B500-3BFBF3D4DE3D   # iPhone Air         — joiner
C=E098270B-C0FA-49DA-9CE6-ADE9B2F1AAC6   # iPhone 17          — joiner

udid_for() {
  case "$1" in
    A|a|leader) echo "$A" ;;
    B|b) echo "$B" ;;
    C|c) echo "$C" ;;
    *) echo "$1" ;;
  esac
}

case "${1:-setup}" in

setup)
  echo "▸ booting simulators"
  for u in $A $B $C; do xcrun simctl boot "$u" 2>/dev/null || true; done
  for u in $A $B $C; do xcrun simctl bootstatus "$u" -b >/dev/null; done

  echo "▸ building"
  xcodebuild build -scheme Wandr -destination "id=$A" -quiet

  APP=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Wandr-*/Build/Products/Debug-iphonesimulator/Wandr.app | head -1)
  echo "▸ installing $APP"
  for u in $A $B $C; do xcrun simctl install "$u" "$APP"; done

  echo "▸ launching"
  # The leader skips intake via the existing debug hook and lands in curation with the demo decks.
  SIMCTL_CHILD_WANDR_SCREEN=curation xcrun simctl launch "$A" $BUNDLE >/dev/null
  # The joiners start on the resting screen, which is where "Have a code?" lives.
  xcrun simctl launch "$B" $BUNDLE >/dev/null
  xcrun simctl launch "$C" $BUNDLE >/dev/null

  cat <<'EOF'

  ready. In two more terminals:

      Tools/squad-demo.sh relay      (leave visible — it is the ground truth)
      Tools/squad-demo.sh logs

  then, on the simulators:

   A (leader)  swipe a few cards right in two different slots  →  Send to Squad
               read the 6-digit code off the plate
   B and C     "Have a code?" at the top  →  type the six digits  →  they appear as chips on A
   A           Start voting  →  all three switch to the ballot together
   all three   tap a place in each slot; bars move on every screen as each vote lands
               once every slot has a winner the room advances on its own:
               A lands on the schedule, B and C on the waiting screen
   A           drag a block if you like, then Publish  →  all three reveal the same night

EOF
  ;;

relay)
  cd "$ROOT/Tools/WandrRelay"
  exec swift run WandrRelay
  ;;

logs)
  if [ $# -ge 2 ]; then
    u=$(udid_for "$2")
    exec xcrun simctl spawn "$u" log stream --level debug \
      --style compact --predicate 'subsystem == "aryaman.Wandr"'
  fi
  # All three at once, each line tagged with the device it came from.
  for pair in "A:$A" "B:$B" "C:$C"; do
    tag="${pair%%:*}"; u="${pair##*:}"
    xcrun simctl spawn "$u" log stream --level debug --style compact \
      --predicate 'subsystem == "aryaman.Wandr"' 2>/dev/null \
      | sed -u "s/^/[$tag] /" &
  done
  trap 'kill $(jobs -p) 2>/dev/null' EXIT
  wait
  ;;

relaunch)
  u=$(udid_for "${2:-B}")
  xcrun simctl terminate "$u" $BUNDLE 2>/dev/null || true
  xcrun simctl launch "$u" $BUNDLE >/dev/null
  echo "▸ relaunched ${2:-B} — it should rejoin the same room as the same person, vote intact"
  ;;

*)
  echo "usage: $0 {setup|relay|logs [A|B|C]|relaunch [A|B|C]}" >&2
  exit 1
  ;;
esac
