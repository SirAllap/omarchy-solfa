import QtQuick
HostWindow {
  settleMs: 330
  PanelFrame { id: f; open: false; Timer { interval: 100; running: true; onTriggered: f.open = true } }
}
