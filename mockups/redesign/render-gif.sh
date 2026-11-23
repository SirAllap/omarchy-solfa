#!/usr/bin/env bash
# Captures the Demo scene frame by frame offscreen, then builds a GIF with ffmpeg.
# Usage: render-gif.sh <out.gif>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HOME/Documents/projects/agentglass/solfa-redesign/animations.gif}"
QML="${QML_TOOL:-/usr/lib/qt6/bin/qml}"
FRAMES="${FRAMES:-330}"
TMP="$(mktemp -d "${TMPDIR:-$HOME/.cache}/solfa-gif.XXXXXX")"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_FORCE_STDERR_LOGGING=1 QT_SCALE_FACTOR=1
cd "$HERE"
LOG="$("$QML" Demo.qml -- "$TMP" gif "$FRAMES" 0 2>&1 | grep ELAPSED)"
MS="${LOG##*ELAPSED }"
FPS="$(python3 -c "print(round($FRAMES / ($MS / 1000.0), 2))")"
echo "frames=$FRAMES elapsed_ms=$MS fps=$FPS"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" \
  -vf "fps=14,scale=420:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$OUT"
rm -rf "$TMP"
ls -la "$OUT"
