import QtQuick
HostWindow {
  settleMs: 3200
  PanelFrame { hotTab: "library"; Component.onCompleted: { nowPlaying.hotPlay = true; nowPlaying.hotLike = true } }
}
