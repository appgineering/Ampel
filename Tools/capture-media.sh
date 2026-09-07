#!/bin/bash
# Regenerate the promotional assets in docs/media.
#
# Two capture modes, deliberately. Window captures (screencapture -l) contain
# no desktop at all, so the stills composite onto anything and can never leak
# what happens to be on screen. The GIF is a real screen recording, so check
# what is behind the popover before running it.
#
# Requires ffmpeg, and Accessibility permission for the terminal running this
# so the popover can be opened.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=docs/media
WORK=$(mktemp -d)
mkdir -p "$OUT"

swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  Tools/ListWindows.swift -o "$WORK/windows"

# Ampel must not see this machine's real sessions while posing for photos.
HOOK=~/.ampel/bin/ampel-hook
[ -f "$HOOK" ] && mv "$HOOK" "$WORK/hook.off"
restore() { [ -f "$WORK/hook.off" ] && mv "$WORK/hook.off" "$HOOK"; rm -rf "$WORK"; }
trap restore EXIT

seed() {
  printf '{"event":"%s","received_at":%s,"payload":{"session_id":"%s","cwd":"%s"%s}}' \
    "$1" "$(date +%s)" "$2" "$3" "${4:-}" > ~/.ampel/events/.t
  mv ~/.ampel/events/.t ~/.ampel/events/"$(date +%s)-0-$RANDOM.json"
}
click() { osascript -e "tell application \"System Events\" to tell process \"Ampel\" to $1" >/dev/null 2>&1; }
popover_id() { "$WORK/windows" | grep 'layer=25' | head -1 | awk '{print $1}'; }
window_id() { "$WORK/windows" | grep 'layer=0' | head -1 | awk '{print $1}'; }

stage() {
  pkill -f 'Ampel.app/Contents/MacOS/Ampel'; sleep 1
  mkdir -p ~/.ampel/events; rm -f ~/.ampel/events/*.json
  seed SessionStart s1 /Users/dev/Projects/checkout-service
  seed SessionStart s2 /Users/dev/Projects/marketing-site
  seed SessionStart s3 /Users/dev/Projects/design-system
  open /Applications/Ampel.app; sleep 3
}

echo "==> stills"
defaults write com.appgineering.ampel hasOnboarded -bool true
stage
seed UserPromptSubmit s2 /Users/dev/Projects/marketing-site
seed Notification s1 /Users/dev/Projects/checkout-service ',"notification_type":"permission_prompt","message":"Claude needs permission to run: npm run migrate"'
sleep 2
click 'click menu bar item 1 of menu bar 2'; sleep 1.5
screencapture -x -o -l"$(popover_id)" -t png "$OUT/popover.png" && echo "  popover"

read -r X Y <<<"$("$WORK/windows" | grep 'layer=25' | head -1 | awk '{split($2,p,","); print p[1], p[2]}')"
osascript -e "tell application \"System Events\" to click at {$((X+67)), $((Y+334))}" >/dev/null 2>&1
sleep 1.5
for pane in General Usage About; do
  click "click button \"$pane\" of toolbar 1 of window 1"; sleep 1.2
  screencapture -x -o -l"$(window_id)" -t png "$OUT/settings-$(echo $pane | tr A-Z a-z).png" \
    && echo "  settings-$pane"
done

echo "==> setup guide"
pkill -f 'Ampel.app/Contents/MacOS/Ampel'; sleep 1
defaults delete com.appgineering.ampel hasOnboarded 2>/dev/null
open /Applications/Ampel.app; sleep 4
for step in 1-welcome 2-hooks 3-usage 4-appearance; do
  screencapture -x -o -l"$(window_id)" -t png "$OUT/onboarding-$step.png" && echo "  $step"
  click 'click button "Continue" of window 1'; sleep 1.2
done
defaults write com.appgineering.ampel hasOnboarded -bool true

echo "==> recording (this one does capture the screen)"
stage
click 'click menu bar item 1 of menu bar 2'; sleep 1.5
read -r X Y W H <<<"$("$WORK/windows" | grep 'layer=25' | head -1 | \
  awk '{split($2,p,","); split($3,s,"x"); print p[1], p[2], s[1], s[2]}')"
( sleep 2;   seed UserPromptSubmit s1 /Users/dev/Projects/checkout-service
  sleep 2.5; seed PreToolUse       s2 /Users/dev/Projects/marketing-site
  sleep 2.5; seed Notification     s1 /Users/dev/Projects/checkout-service ',"notification_type":"permission_prompt","message":"Claude needs permission to run: npm run migrate"'
  sleep 4.5; seed PostToolUse      s1 /Users/dev/Projects/checkout-service
  sleep 2;   seed Stop             s1 /Users/dev/Projects/checkout-service
  sleep 2;   seed Stop             s2 /Users/dev/Projects/marketing-site
  sleep 1.5 ) &
screencapture -x -v -V 18 -R$((X-70)),0,$((W+140)),$((Y+H+40)) "$WORK/demo.mov"
wait

for spec in "demo:680:11:128" "demo-small:520:9:96"; do
  IFS=: read -r name width fps colors <<<"$spec"
  ffmpeg -y -i "$WORK/demo.mov" -vf "fps=$fps,scale=$width:-1:flags=lanczos,palettegen=max_colors=$colors:stats_mode=diff" \
    "$WORK/$name-pal.png" -loglevel error
  ffmpeg -y -i "$WORK/demo.mov" -i "$WORK/$name-pal.png" \
    -lavfi "fps=$fps,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$OUT/$name.gif" -loglevel error
  echo "  $name.gif $(du -h "$OUT/$name.gif" | cut -f1)"
done

echo "==> done"
