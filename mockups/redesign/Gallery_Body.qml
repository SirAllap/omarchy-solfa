import QtQuick

// The panels (live, scaled to 46 %) and, below them, the motion lab.
Item {
  id: g
  width: 5 * 300 + 4 * 14
  height: 3 * 402 + 40 + 2 * 250 + 14 + 30
  readonly property var cells: [
    ["Queue", { tab: "queue" }], ["Search", { tab: "search", viewMode: "results" }], ["Library", { tab: "library", viewMode: "playlists" }],
    ["Lyrics", { tab: "lyrics" }], ["History", { tab: "history" }], ["Album page", { overlay: "detail", detailKind: "album" }],
    ["Artist page", { overlay: "detail", detailKind: "artist" }], ["Settings: Sound", { overlay: "settings", settingsSection: "sound" }], ["Settings: Account", { overlay: "settings", settingsSection: "account" }],
    ["Sign-in", { overlay: "signin", signInState: "signedout" }], ["Cookie question", { overlay: "signin", signInState: "cookie" }], ["Paused", { np: "paused" }],
    ["Advert", { np: "ad" }], ["Nothing playing", { np: "empty", tab: "search", viewMode: "idle" }], ["Engine off", { np: "off" }],
    ["Loading", { np: "loading", viewMode: "loading" }], ["Empty queue", { viewMode: "empty" }], ["Error", { tab: "library", viewMode: "error" }] ]
  Repeater {
    model: g.cells
    Item {
      x: (index % 6) * 238; y: Math.floor(index / 6) * 402
      width: 224; height: 388
      Item { width: 460; height: 780; scale: 0.4565; transformOrigin: Item.TopLeft
        Loader { sourceComponent: pf; onLoaded: { var o = modelData[1]; for (var k in o) item[k] = o[k] } } }
      Text { y: 362; text: modelData[0]; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
  }
  Text { y: 3 * 402 + 2; text: "MOTION  (ideas from a study of the MIT project HANCORE-linux/rumb; no code or assets copied)"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.4 }
  MotionLab { x: 0; y: 3 * 402 + 30 }
  Component { id: pf; PanelFrame {} }
}
