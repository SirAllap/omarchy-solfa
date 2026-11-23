import QtQuick

// The whole panel: header and now-playing, tabs, one view, a hint line, and
// sheets that slide over it (a page, Settings, sign-in). Fake data only.
Item {
  id: f
  width: 460
  height: 780
  property string tab: "queue"
  property string overlay: ""          // "" | detail | settings | signin
  property string np: "playing"        // NowPlaying mode
  property string viewMode: "normal"   // forwarded to the open view
  property string detailKind: "album"
  property string detailMode: "normal"
  property string settingsSection: "sound"
  property string settingsMode: "normal"
  property string signInState: "signedout"
  property string toast: ""
  property string toastKind: "info"
  property string hotTab: ""
  property real progress: 0.38
  property int lyricIdx: 3
  property bool showOff: np === "off"
  property bool open: true
  property int trackIdx: 0
  onOpenChanged: { Motion.panelOpen = open }
  onNpChanged: Motion.playing = (np === "playing" || np === "ad")
  // Events: a glow in the colour of what happened, fading like exp(-t/520 ms).
  function event(kind) {
    var p
    if (kind === "like") p = nowp.buttons.like.mapToItem(f, 18, 18)
    else if (kind === "queue" || kind === "next") p = tabs0.tabCenter("queue")
    else if (kind === "error") p = Qt.point(230, 690)
    else p = Qt.point(20 + 56, 16 + 44 + 54)
    if (kind === "queue" || kind === "next") p = Qt.point(20 + p.x, 350 + p.y)
    evg.x = p.x; evg.y = p.y
    evg.fire(kind)
  }
  function comet(x, y, seed) { cm.fly(x, y, 20 + tabs0.tabCenter("queue").x, 350 + tabs0.tabCenter("queue").y, "next", seed || 3) }
  property alias nowPlaying: nowp
  readonly property var tabs: [
    { key: "queue", label: "Queue", icon: "queue" }, { key: "search", label: "Search", icon: "search" },
    { key: "library", label: "Library", icon: "library" }, { key: "lyrics", label: "Lyrics", icon: "lyrics" },
    { key: "history", label: "History", icon: "history" } ]
  // "normal" means the usual look of whichever view is open
  function vm(def) { return viewMode === "normal" ? def : viewMode }
  readonly property var tabKeys: tabs.map(function (t) { return t.key })
  readonly property var hints: overlay === "detail" ? [["↵", "play or open"], ["e", "play next"], ["esc", "back"]]
    : tab === "queue" ? [["↵", "play"], ["x", "remove"], ["J K", "move"]]
    : tab === "search" ? [["↵", "play"], ["tab", "filter"], ["esc", "clear"]]
    : tab === "library" ? [["↵", "play or open"], ["[ ]", "section"], ["e", "play next"]]
    : tab === "lyrics" ? [["j k", "scroll"], [", .", "seek"]] : [["↵", "play"], ["e", "play next"]]

  Rectangle { anchors.fill: parent; radius: 26; color: Theme.surface; border.width: 1; border.color: Theme.hair }
  Item { anchors.fill: parent; clip: true
    Glow { x: -60; y: -120; width: 600; height: 440; color: Theme.hue(nowp.has ? nowp.track.seed : 9, 0.5); strength: nowp.has ? 0.26 : 0.1
      Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 700 } } Behavior on strength { enabled: !Motion.reduce; NumberAnimation { duration: 500 } } } }

  WaveItem { x: 20; y: 16; width: 420; height: 322; priority: 0; go: f.open
    NowPlaying { id: nowp; width: 420; mode: f.np; track: Fake.tracks[f.trackIdx]; progress: f.progress; opacity: f.overlay === "settings" ? 0 : 1; onMoment: function (k) { f.event(k) }
      Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 200 } } } }
  WaveItem { x: 20; y: 350; width: 420; height: 46; priority: 0; go: f.open
  TabBar { id: tabs0; width: 420; tabs: f.tabs; current: f.overlay === "detail" ? "" : f.tab; hotKey: f.hotTab; onPicked: function (k) { f.tab = k } } }

  // ---- views
  Item { id: body; x: 20; y: 410; width: 420; height: 318; clip: true; visible: !f.showOff
    QueueView { id: qv; width: parent.width; height: parent.height; property bool on: f.tab === "queue"; active: on && f.overlay === "" && f.open; mode: on ? f.viewMode : "normal"; opacity: on ? 1 : 0; x: on ? 0 : (f.tabKeys.indexOf("queue") < f.tabKeys.indexOf(f.tab) ? -30 : 30); visible: opacity > 0.01 }
    SearchView { id: sv; width: parent.width; height: parent.height; property bool on: f.tab === "search"; active: on && f.overlay === "" && f.open; mode: on ? f.vm("results") : "results"; opacity: on ? 1 : 0; x: on ? 0 : (f.tabKeys.indexOf("search") < f.tabKeys.indexOf(f.tab) ? -30 : 30); visible: opacity > 0.01 }
    LibraryView { id: lv; width: parent.width; height: parent.height; property bool on: f.tab === "library"; active: on && f.overlay === "" && f.open; mode: on ? f.vm("playlists") : "playlists"; opacity: on ? 1 : 0; x: on ? 0 : (f.tabKeys.indexOf("library") < f.tabKeys.indexOf(f.tab) ? -30 : 30); visible: opacity > 0.01 }
    LyricsView { id: yv; cur: f.lyricIdx; width: parent.width; height: parent.height; property bool on: f.tab === "lyrics"; active: on && f.overlay === "" && f.open; mode: on ? f.vm("synced") : "synced"; opacity: on ? 1 : 0; x: on ? 0 : (f.tabKeys.indexOf("lyrics") < f.tabKeys.indexOf(f.tab) ? -30 : 30); visible: opacity > 0.01 }
    HistoryView { id: hv; width: parent.width; height: parent.height; property bool on: f.tab === "history"; active: on && f.overlay === "" && f.open; mode: on ? f.viewMode : "normal"; opacity: on ? 1 : 0; x: on ? 0 : (f.tabKeys.indexOf("history") < f.tabKeys.indexOf(f.tab) ? -30 : 30); visible: opacity > 0.01 }
  }
  // fade at the bottom of the list
  Rectangle { x: 20; y: 700; width: 420; height: 34; visible: !f.showOff; gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Theme.surface } } }
  OffCard { x: 20; y: 410; width: 420; height: 318; visible: f.showOff; active: f.showOff }

  // ---- hint line
  WaveItem { x: 0; y: 738; width: 460; height: 28; priority: 2; go: f.open
  Row { x: 24; y: 4; spacing: 16
    Repeater { model: f.hints; KeyCap { keys: modelData[0]; label: modelData[1] } } }
  Text { x: 460 - 24 - width; y: 6; text: "? all keys"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
  }

  // ---- a page (album, artist) slides over the tabs
  Rectangle { id: sheet; x: 0; y: 340; width: parent.width; height: parent.height - 340; radius: 26; color: Theme.surface
    visible: opacity > 0.01; opacity: f.overlay === "detail" ? 1 : 0
    transform: Translate { x: f.overlay === "detail" ? 0 : 90; Behavior on x { enabled: !Motion.reduce; SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.3 } } }
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 200 } }
    DetailView { x: 20; y: 8; width: 420; height: parent.height - 16; kind: f.detailKind; mode: f.detailMode; active: f.overlay === "detail" } }

  // ---- Settings replaces the panel
  Rectangle { id: settings; width: parent.width; height: parent.height; radius: 26; color: Theme.surface; border.width: 1; border.color: Theme.hair
    visible: opacity > 0.01; opacity: f.overlay === "settings" ? 1 : 0
    scale: f.overlay === "settings" ? 1 : 0.96
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 220 } }
    Behavior on scale { enabled: !Motion.reduce; SpringAnimation { spring: 5; damping: 0.5; epsilon: 0.001 } }
    Glow { x: -80; y: -120; width: 560; height: 420; color: Theme.accent; strength: 0.14 }
    SettingsView { anchors.fill: parent; section: f.settingsSection; mode: f.settingsMode; active: f.overlay === "settings" } }

  // ---- sign-in sheet
  Rectangle { anchors.fill: parent; radius: 26; color: "#000"; opacity: f.overlay === "signin" ? 0.62 : 0; visible: opacity > 0.01; Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 240 } } }
  SignInCard { id: sic; anchors.horizontalCenter: parent.horizontalCenter; state: f.signInState
    y: f.overlay === "signin" ? 190 : 260; opacity: f.overlay === "signin" ? 1 : 0; visible: opacity > 0.01
    scale: f.overlay === "signin" ? 1 : 0.94
    Behavior on y { enabled: !Motion.reduce; SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.3 } }
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 220 } }
    Behavior on scale { enabled: !Motion.reduce; SpringAnimation { spring: 5; damping: 0.5; epsilon: 0.001 } } }

  // ---- a short message that drops in from the top
  Rectangle { id: toast; anchors.horizontalCenter: parent.horizontalCenter; height: 40; radius: 20; width: trow.width + 34
    y: f.toast !== "" ? 676 : 800; opacity: f.toast !== "" ? 1 : 0
    Behavior on y { enabled: !Motion.reduce; SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.3 } }
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 180 } }
    color: Theme.raised; border.width: 1; border.color: f.toastKind === "error" ? Theme.a(Theme.err, 0.6) : Theme.a(Theme.accent, 0.5)
    Glow { anchors.centerIn: parent; width: parent.width * 1.6; height: 120; color: f.toastKind === "error" ? Theme.err : Theme.accent; strength: 0.22 }
    Row { id: trow; anchors.centerIn: parent; spacing: 8
      Icon { anchors.verticalCenter: parent.verticalCenter; name: f.toastKind === "error" ? "warn" : "check"; size: 16; color: f.toastKind === "error" ? Theme.err : Theme.ok }
      Text { anchors.verticalCenter: parent.verticalCenter; text: f.toast; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold } } }

  // ---- things that fly or glow above everything
  EventGlow { id: evg }
  Comet { id: cm; z: 50; onArrived: f.event("queue") }
}
