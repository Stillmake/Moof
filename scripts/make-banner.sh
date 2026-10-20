#!/bin/zsh

# Usage:
# ./scripts/make-banner.sh
# Builds the README banner (assets/banner.avif) and a video of it for social media
# (build/banner.mov) from the real app, deterministically:
# 1. Builds Debug and launches it in banner mode (Moof/Debug/MoofBannerRecorder.swift), which
#    shows one scene per theme over scripts/banner-background.jpg and captures one still of each
#    once its cards are at rest: build/banner-scenes/scene-<n>.png.
# 2. Encodes the stills as an animated AVIF with ffmpeg: each scene shown for HOLD seconds, looping,
#    at the capture's full 2720 × 1044px. AV1 at CRF 18 with full 4:4:4 color, BT.709-tagged, keeps
#    text and glass edges clean in ~100 KB; like a GIF it autoplays in `![](…)`.
# 3. Encodes the same stills as an H.264 MOV for social media: 30 fps, 4:2:0, BT.709-tagged, with
#    the index up front for streaming. Platforms re-encode uploads, so it favors compatibility.
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
mkdir -p assets
ffmpeg -loglevel error -y -framerate "1/$HOLD" -i "$SCENES/scene-%d.png" \
  -vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv444p" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -c:v libaom-av1 -crf 18 -cpu-used 4 -loop 0 assets/banner.avif
echo "assets/banner.avif $(du -h assets/banner.avif | cut -f1)"
ffmpeg -loglevel error -y -framerate "1/$HOLD" -i "$SCENES/scene-%d.png" \
  -vf "fps=30,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -c:v libx264 -preset slow -crf 18 -tune stillimage -x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709 \
  -movflags +faststart+write_colr build/banner.mov
echo "build/banner.mov $(du -h build/banner.mov | cut -f1)"
