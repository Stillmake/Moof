#!/bin/zsh

# Usage:
# ./scripts/make-screenshots.sh
# Builds the Mac App Store screenshots (build/screenshots/scene-<n>.png) from the real app:
# Debug launched in screenshot mode (Moof/Debug/MoofBannerRecorder.swift) shows one headlined scene
# per theme over scripts/banner-background.jpg, aspect-filled, and captures each at 2880 × 1800px,
# the largest 16:10 size App Store Connect accepts, as opaque PNGs.
#
# Requirements: Xcode, and a main display of at least 1440 × 900pt visible at 2× (Retina). It draws
# on screen for a few seconds under the menu bar. Saved cards are backed up and restored around it.

set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="build/banner-dd"
SCENES="build/screenshots"
STATE="$HOME/Library/Application Support/com.stillmake.Moof/notifications.json"
BACKUP="build/screenshots-state-backup.json"

die() { echo "Error: $*" >&2; exit 1; }

echo "== Build Debug =="
xcodebuild -project Moof.xcodeproj -scheme Moof -configuration Debug -derivedDataPath "$DERIVED" -quiet build

# Showing and closing cards rewrites the saved cards; put them back afterwards.
mkdir -p build
rm -f "$BACKUP"
[[ -f "$STATE" ]] && cp "$STATE" "$BACKUP"
restore_state() { [[ -f "$BACKUP" ]] && cp "$BACKUP" "$STATE" || rm -f "$STATE"; }
trap restore_state EXIT

echo "== Capture scenes =="
"$DERIVED/Build/Products/Debug/Moof.app/Contents/MacOS/Moof" \
  -MoofScreenshotScenes "$PWD/$SCENES" \
  -MoofBannerBackground "$PWD/scripts/banner-background.jpg"

for still in "$SCENES"/scene-*.png(N); do
  size=$(sips -g pixelWidth -g pixelHeight "$still" | awk '/pixel/ { printf "%s ", $2 }')
  [[ "$size" == "2880 1800 " ]] || die "$still is $size, not 2880 × 1800 (needs a 2× display)."
  echo "$still"
done
