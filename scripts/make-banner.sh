#!/bin/zsh

# Usage:
# ./scripts/make-banner.sh
# Builds the README banner video (build/banner.mp4, uploaded to GitHub by hand) from the real app,
# deterministically:
# 1. Builds Debug and launches it in banner mode (Moof/Debug/MoofBannerRecorder.swift), which
#    shows one scene per theme over scripts/banner-background.jpg and captures one still of each
#    once its cards are at rest: build/banner-scenes/scene-<n>.png.
# 2. Encodes the stills as an H.264 video with ffmpeg: each scene shown for HOLD seconds at 10 fps,
#    at the capture's full 2720 × 1044px, the background's own size. Converted with the BT.709
#    matrix and tagged as such, so players do not guess the colors.
#
# Requirements: Xcode, ffmpeg (brew install ffmpeg). Step 1 draws on screen for a few seconds under
# the menu bar. Saved cards are backed up and restored around it.

set -euo pipefail
cd "$(dirname "$0")/.."

HOLD=2
DERIVED="build/banner-dd"
SCENES="build/banner-scenes"
STATE="$HOME/Library/Application Support/com.stillmake.Moof/notifications.json"
BACKUP="build/banner-state-backup.json"

die() { echo "Error: $*" >&2; exit 1; }
command -v ffmpeg >/dev/null || die "ffmpeg not found (brew install ffmpeg)."

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
  -MoofBannerScenes "$PWD/$SCENES" \
  -MoofBannerBackground "$PWD/scripts/banner-background.jpg"
STILLS=("$SCENES"/scene-*.png(N))
[[ "${#STILLS[@]}" -gt 1 ]] || die "expected several scenes, got ${#STILLS[@]}."
echo "${#STILLS[@]} scenes"

echo "== Encode =="
ffmpeg -loglevel error -y -framerate "1/$HOLD" -i "$SCENES/scene-%d.png" \
  -vf "fps=10,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -c:v libx264 -preset slow -crf 18 -tune stillimage -x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709 \
  -movflags +faststart+write_colr build/banner.mp4
echo "build/banner.mp4 $(du -h build/banner.mp4 | cut -f1)"
