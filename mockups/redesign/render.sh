#!/usr/bin/env bash
# Renders every mockup scene offscreen (no window on any desktop) to PNGs.
# Usage: render.sh <output-dir>   (default ~/Documents/projects/agentglass/solfa-redesign)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HOME/Documents/projects/agentglass/solfa-redesign}"
QML="${QML_TOOL:-/usr/lib/qt6/bin/qml}"
mkdir -p "$OUT"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_FORCE_STDERR_LOGGING=1
cd "$HERE"
render() { # name scene
  QT_SCALE_FACTOR=2 timeout 90 "$QML" "$2.qml" -- "$OUT/$1.png" 2>&1 | grep -vE 'qt.qpa|^$' | sed "s/^/[$1] /"
}
while read -r name scene; do
  [ -z "$name" ] && continue
  render "$name" "$scene" &
  while [ "$(jobs -r | wc -l)" -ge 4 ]; do sleep 0.3; done
done < scenes.txt
wait
ls "$OUT"/*.png | wc -l
