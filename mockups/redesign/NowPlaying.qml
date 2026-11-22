import QtQuick

// The top of the panel: cover, song, seek bar, every control.
// mode: playing | paused | empty | ad | loading | off
Item {
  id: np
  property string mode: "playing"
  property real progress: 0.38
  property bool liked: true
  property bool hotPlay: false
  property bool hotLike: false
  property bool shuffleOn: true
  property bool repeatOn: false
  property bool sleepOn: false
  readonly property bool has: mode === "playing" || mode === "paused" || mode === "ad"
  readonly property bool isPlaying: mode === "playing" || mode === "ad"
  property var track: Fake.tracks[0]
  property real volume: 0.72
  signal playToggled()
  signal moment(string kind)      // something happened: the panel lights it up
  property string hotName: ""
  property int idleSeed: 1
  property alias idleMs: idleTimer.interval
  readonly property var buttons: ({ shuffle: shufB, prev: prevB, play: playB, next: nextB, repeat: repB, like: likeB })

  // The cover glances at the control that was just used, then comes back.
  function look(item) {
    var p = item.mapToItem(hero, item.width / 2, item.height / 2)
    var dx = p.x - (cover.x + cover.width / 2), dy = p.y - (cover.y + cover.height / 2)
    var L = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    cover.gx = dx / L * 8; cover.gy = dy / L * 8
    back.restart()
  }
  function press(name) {
    hotName = name; hotOff.restart()
    look(buttons[name])
    idleTimer.restart()
    if (name === "like") moment("like")
    else if (name === "next" || name === "prev") moment("track")
  }
  Timer { id: back; interval: Motion.glanceMs + 500; onTriggered: { cover.gx = 0; cover.gy = 0 } }
  Timer { id: hotOff; interval: 360; onTriggered: np.hotName = "" }
  // After a quiet while the cover looks somewhere else, always the same way for the same seed.
  Timer { id: idleTimer; interval: Motion.idleMs; repeat: true; running: np.has && Motion.live
    onTriggered: { var a = Motion.rand(np.idleSeed++) * 6.283; cover.gx = Math.cos(a) * 7; cover.gy = Math.sin(a) * 7; back.interval = Motion.glanceMs; back.restart() } }
  height: 322
  width: 420

  // ---- title row
  Row {
    id: head
    x: 0; y: 0; height: 32; spacing: 8
    Logo { size: 28; anchors.verticalCenter: parent.verticalCenter }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Solfa"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: -0.3 }
    Rectangle { visible: np.mode !== "off"; anchors.verticalCenter: parent.verticalCenter; width: pt.width + 16; height: 20; radius: 10; color: Theme.a(Theme.accent2, 0.16); border.width: 1; border.color: Theme.a(Theme.accent2, 0.4)
      Text { id: pt; anchors.centerIn: parent; text: "Premium"; color: Theme.accent2; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold } }
  }
  Row {
    anchors.right: parent.right; y: 0; spacing: 2
    IconButton { icon: "gear"; size: 32; glyph: 17; tip: "Settings" }
    IconButton { icon: "close"; size: 32; glyph: 16 }
  }

  // ---- hero
  Item {
    id: hero
    y: 44; width: parent.width; height: 108
    Cover { id: cover; x: 4; y: 2; width: 104; height: 104; radius: 22; seed: np.has ? np.track.seed : 9; breathe: np.has; playing: np.isPlaying; lit: np.has
      visible: np.has }
    Rectangle { visible: !np.has; x: 4; y: 2; width: 104; height: 104; radius: 22; color: Theme.wash; border.width: 1; border.color: Theme.hair
      Icon { anchors.centerIn: parent; name: np.mode === "off" ? "power" : "album"; size: 34; color: Theme.faint }
      Spinner { visible: np.mode === "loading"; anchors.centerIn: parent; size: 44 } }
    Column {
      x: 128; width: parent.width - 128 - 44; anchors.verticalCenter: parent.verticalCenter; spacing: 4
      Rectangle { visible: np.mode === "ad"; height: 20; width: adt.width + 16; radius: 10; color: Theme.a(Theme.warn, 0.16); border.width: 1; border.color: Theme.a(Theme.warn, 0.4)
        Text { id: adt; anchors.centerIn: parent; text: "Advert · your song starts in 0:12"; color: Theme.warn; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold } }
      Typewriter { width: parent.width; maxLines: 2; pixelSize: 21; weight: Font.Bold; color: Theme.fg
        text: np.has ? (np.mode === "ad" ? "Advert" : np.track.t) : np.mode === "loading" ? "Starting YouTube Music…" : np.mode === "off" ? "Solfa is off" : "Nothing playing" }
      Text { width: parent.width; elide: Text.ElideRight; wrapMode: Text.WordWrap; maximumLineCount: 2
        text: np.has ? (np.mode === "ad" ? "Your song starts after it" : np.track.a + " · " + np.track.al) : np.mode === "loading" ? "Getting the player ready" : np.mode === "off" ? "Nothing plays until you turn it on." : "Press / to search, or pick something below."
        color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 }
    }
    IconButton { id: likeB; visible: np.has; anchors.right: parent.right; y: 4; icon: "heart"; size: 36; glyph: 20; filled: np.liked; active: np.liked; hot: np.hotLike || np.hotName === "like"; tip: "Like (l)"; onClicked: np.press("like") }
  }

  // ---- seek
  Item {
    y: 164; width: parent.width; height: 40
    opacity: np.mode === "ad" ? 0.5 : 1
    ProgressBar { width: parent.width; value: np.has ? np.progress : 0; playing: np.mode === "playing"; dim: !np.has }
    Text { y: 24; text: np.has ? "1:19" : "0:00"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
    Text { y: 24; anchors.right: parent.right; text: np.has ? np.track.d : "0:00"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
  }

  // ---- transport
  Row {
    y: 212; anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
    opacity: np.has || np.mode === "empty" ? 1 : 0.5
    IconButton { id: shufB; icon: "shuffle"; active: np.shuffleOn; enabled2: np.has; tip: "Shuffle"; hot: np.hotName === "shuffle"; onClicked: np.press("shuffle") }
    IconButton { id: prevB; icon: "prev"; size: 42; glyph: 20; enabled2: np.has; hot: np.hotName === "prev"; onClicked: np.press("prev") }
    IconButton { id: playB; icon: np.isPlaying ? "pause" : "play"; size: 62; glyph: 26; primary: true; hot: np.hotPlay || np.hotName === "play"; enabled2: np.has; onClicked: { np.press("play"); np.playToggled() } }
    IconButton { id: nextB; icon: "next"; size: 42; glyph: 20; enabled2: np.has && np.mode !== "ad"; hot: np.hotName === "next"; onClicked: np.press("next") }
    IconButton { id: repB; icon: "repeat"; active: np.repeatOn; enabled2: np.has; hot: np.hotName === "repeat"; onClicked: np.press("repeat") }
  }
  Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 200 } }

  // ---- volume, sleep, radio
  Row {
    y: 286; width: parent.width; spacing: 12
    Icon { anchors.verticalCenter: parent.verticalCenter; name: np.volume === 0 ? "mute" : "volume"; size: 18; color: Theme.dim }
    Slider { width: parent.width - 18 - 12 * 3 - sl.width - rad.width; anchors.verticalCenter: parent.verticalCenter; value: np.volume; labelRight: Math.round(np.volume * 100) + "%" }
    Btn { id: sl; compact: true; icon: "moon"; text: np.sleepOn ? "Sleep 28:40" : "Sleep"; kind: np.sleepOn ? "primary" : "quiet"; anchors.verticalCenter: parent.verticalCenter }
    Btn { id: rad; compact: true; icon: "radio"; text: "Radio"; anchors.verticalCenter: parent.verticalCenter }
  }
}
