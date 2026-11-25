#!/usr/bin/env bash
# Renders the four guide videos into assets/guide/ from the guide's own
# animation (PhoneHandAnimation): 540x960, 30 fps, 12 s (two rounds),
# H.264 High, yuv420p, no audio, +faststart. Needs flutter, ffmpeg (libx264)
# and ffprobe on PATH. Run from anywhere: bash tool/guide/make_videos.sh
set -euo pipefail

cd "$(dirname "$0")/../.."

GUIDE_FRAMES=$(mktemp -d)
export GUIDE_FRAMES
trap 'rm -rf "$GUIDE_FRAMES"' EXIT

flutter test tool/guide/render_frames_test.dart

names=(shortcut action_button back_tap outlook)

for name in "${names[@]}"; do
  ffmpeg -y -loglevel error -framerate 30 -i "$GUIDE_FRAMES/$name/%04d.png" \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 26 \
    -movflags +faststart -an "assets/guide/$name.mp4"
done

for name in "${names[@]}"; do
  echo "== assets/guide/$name.mp4 ($(wc -c < "assets/guide/$name.mp4") bytes)"
  ffprobe -v error -show_entries stream=codec_name,width,height:format=duration -of default=nw=1 \
    "assets/guide/$name.mp4"
done
