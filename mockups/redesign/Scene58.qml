import QtQuick
HostWindow {
  settleMs: 470
  PanelFrame { id: f; Timer { interval: 200; running: true; onTriggered: { f.trackIdx = 3; f.event("track") } } }
}
