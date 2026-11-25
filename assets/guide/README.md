# Guide videos

Short guide videos for the "Shortcuts & Siri" guide (design §10). Each one plays
silently in Picture in Picture after "Open Settings" is tapped, so it keeps playing
over the Settings app.

- One file per guide step, named in snake_case: `shortcut.mp4`, `action_button.mp4`,
  `back_tap.mp4`, `outlook.mp4`.
- Each video is at most 20 seconds, H.264, with no audio track.
- The first release renders them from the guide's own Flutter animation; real iPhone
  recordings may replace them later under the same names.

Regenerate them with `bash tool/guide/make_videos.sh` (needs flutter, ffmpeg with libx264
and ffprobe): 540×960, 30 fps, 12 seconds (two rounds of the animation), H.264 High,
`yuv420p`, no audio, `+faststart`, at most 600 KB each, on the light theme's surface and
with no text.
