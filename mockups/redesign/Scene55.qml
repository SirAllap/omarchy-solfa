import QtQuick
HostWindow {
  settleMs: 470
  PanelFrame { id: f; Timer { interval: 200; running: true; onTriggered: f.nowPlaying.press("like") } }
}
