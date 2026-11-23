import QtQuick
HostWindow {
  settleMs: 560
  PanelFrame { id: f; tab: "search"; viewMode: "results"; Timer { interval: 150; running: true; onTriggered: f.comet(360, 590, 5) } }
}
