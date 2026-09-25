#!/usr/bin/env bash
# qmllint against the real shell modules (qs.Ui, qs.Commons). Fails on any
# warning except the ones that come from the shell's dynamic objects
# (`bar`, `svc` are QtObject/var, so their members are unknown to the linter).
set -uo pipefail
cd "$(dirname "$0")/.."
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
SHELL_DIR="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
[[ -x "$QMLLINT" && -d "$SHELL_DIR/Ui" ]] || { echo "qmllint or the Omarchy shell is missing; skipping"; exit 0; }
IMPORTS="$(mktemp -d "${TMPDIR:-/tmp}/solfa-qml.XXXXXX")"
trap 'rm -rf -- "$IMPORTS"' EXIT
mkdir -p "$IMPORTS/qs"
ln -s "$SHELL_DIR/Ui" "$IMPORTS/qs/Ui"
ln -s "$SHELL_DIR/Commons" "$IMPORTS/qs/Commons"
out="$("$QMLLINT" -I "$IMPORTS" -I /usr/lib/qt6/qml Service.qml BarWidget.qml Panel.qml views/*.qml 2>&1)"
real="$(printf '%s\n' "$out" | grep -E '^(Warning|Error)' \
  | grep -v 'not found on type "QObject"' \
  | grep -v 'QProcess::ExitStatus' \
  | grep -v 'QVariantMap to QVariantHash' \
  | grep -v -i 'unqualified access' || true)"
if [[ -n "$real" ]]; then
  printf '%s\n' "$real"
  echo "qmllint: $(printf '%s\n' "$real" | wc -l) warning(s)"
  exit 1
fi
echo "qmllint: clean ($(ls Service.qml BarWidget.qml Panel.qml views/*.qml | wc -l) files)"
