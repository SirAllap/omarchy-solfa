import QtQuick
HostWindow {
  settleMs: 430
  PanelFrame { id: f; tab: "search"; viewMode: "results"; Timer { interval: 200; running: true; onTriggered: f.event("queue") } }
}
