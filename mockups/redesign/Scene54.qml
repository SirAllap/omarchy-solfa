import QtQuick
HostWindow {
  settleMs: 640
  PanelFrame { id: f; Timer { interval: 200; running: true; onTriggered: f.nowPlaying.press("next") } }
}
