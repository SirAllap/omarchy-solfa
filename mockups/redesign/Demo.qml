import QtQuick

// The animated tour: tabs morph, rows slide in, the cover breathes, the
// progress glows, a page and Settings slide over. Captured to a GIF.
HostWindow {
  id: d
  settleMs: 600
  property int t: 0
  PanelFrame { id: f; progress: 0.12; np: "playing"; tab: "queue" }
  readonly property var steps: [
    [0, function () { f.tab = "queue" }],
    [1200, function () { f.nowPlaying.press("next") }],
    [2600, function () { f.nowPlaying.press("prev") }],
    [4000, function () { f.nowPlaying.press("like") }],
    [5600, function () { f.tab = "search"; f.viewMode = "results" }],
    [6400, function () { f.comet(360, 590, 5) }],
    [8000, function () { f.tab = "lyrics"; f.viewMode = "synced" }],
    [9000, function () { f.lyricIdx = 4 }],
    [10000, function () { f.lyricIdx = 5 }],
    [11400, function () { f.tab = "queue"; f.viewMode = "normal"; f.trackIdx = 3; f.event("track") }],
    [13200, function () { f.overlay = "detail"; f.detailKind = "album" }],
    [14800, function () { f.overlay = "" }],
    [15000, function () { f.open = false }],
    [15500, function () { f.open = true }],
    [18500, function () { f.overlay = "settings"; f.settingsSection = "advanced"; Motion.reduce = true }],
    [21000, function () { Motion.reduce = false; f.overlay = "" }]
  ]
  property int next: 0
  Timer { interval: 50; running: true; repeat: true
    onTriggered: {
      d.t += 50
      f.progress = Math.min(0.95, 0.12 + d.t / 24000)
      while (d.next < d.steps.length && d.steps[d.next][0] <= d.t) { d.steps[d.next][1](); d.next++ }
    } }
}
