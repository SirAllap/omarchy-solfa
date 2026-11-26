import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The PR screenshots of the Off state (#33), from the real QML: the bar widget and the real
// Panel.qml, each state saved as its own PNG in $SOLFA_SHOT_OUT. $SOLFA_SHOT_SET is "before"
// (main's code) or "after". Invented song only; the cover is the generated gradient in
// $SOLFA_SHOT_COVER. Every grab waits for the animations to end, and the pointer moves on only
// after the grab is saved. Run by tests/bar_off_shots.py (offscreen, 2x). Never the live desktop.
ShellRoot {
  id: scene
  readonly property bool before: Quickshell.env("SOLFA_SHOT_SET") === "before"

  component FakeSvc: QtObject {
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: !closed
    property bool hasTrack: !closed
    property bool isPlaying: !closed
    property bool isAd: false
    property bool adSkippable: false
    property bool signedIn: true
    property string panelKeyLabel: "Super+Shift+M"
    property var panelKeyChosen: ({ keys: "SUPER + SHIFT + M" })
    property var playPauseKeyChosen: ({ keys: "SUPER + ALT + P" })
    property string playPauseKeyLabel: "Super+Alt+P"
    property var panelKeyOptions: ["", "SUPER + SHIFT + M"]
    property bool premium: false
    property string like: "LIKE"
    property string title: hasTrack ? "Northern Lights" : ""
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: closed ? "Solfa is off" : ""
    property string thumb: ""
    property string lastTitle: ""
    property string lastThumb: ""
    property string lastArtist: ""
    property string lastAlbum: ""
    property real lastPosition: -1
    property real lastDuration: 0
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property string repeatMode: "ALL"
    property int volume: 60
    property bool muted: false
    property string videoId: hasTrack ? "v1" : ""
    property var engine: ({ status: closed ? "stopped" : "ready", wantRunning: !closed })
    property var calls: []
    property var settings: ({})
    property int fastClockUsers: 0
    function toggleEngine() { calls.push("toggleEngine") }
    function startEngine() { calls.push("startEngine") }
    function startAndPlay() { calls.push("startAndPlay") }
    function togglePlaying() { calls.push("togglePlaying") }
    function previous() {}
    function next() {}
    function toggleLike() {}
    function skipAd() {}
    function seek(v) {}
    function shuffle() {}
    function cycleRepeat() {}
    function toggleMute() {}
    function setVolume(v) {}
  }

  FakeSvc { id: barSvc; closed: true; hasTrack: false; isPlaying: false
    property string lastArtist: "The Quiet Tides"
    lastTitle: scene.before ? "" : "Glass Harbour"; lastThumb: scene.before ? "" : "file://" + Quickshell.env("SOLFA_SHOT_COVER") }

  component FakeBar: QtObject {
    property var svc: null
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property var shell: QtObject { function serviceFor(id) { return svc } }
    property string tip: ""
    function showTooltip(item, text) { tip = text }
    function hideTooltip(item) {}
  }

  FakeBar { id: shotBar; svc: barSvc }

  QtObject {
    id: fakeSvc
    property bool starting: false
    property bool signInWhenUp: false
    property string lastTitle: "Glass Harbour"
    property string lastArtist: "The Quiet Tides"
    property string lastAlbum: "Low Light"
    property real lastPosition: 102
    property real lastDuration: 238
    property string lastThumb: "file://" + Quickshell.env("SOLFA_SHOT_COVER")
    function startAndPlay() {}
    property bool bridgeUp: true
    property bool ready: true
    property bool signingIn: false
    property bool gated: false
    property bool closed: false
    property bool signedIn: true
    property string panelKeyLabel: "Super+Shift+M"
    property var panelKeyChosen: ({ keys: "SUPER + SHIFT + M" })
    property var playPauseKeyChosen: ({ keys: "SUPER + ALT + P" })
    property string playPauseKeyLabel: "Super+Alt+P"
    property var panelKeyOptions: ["", "SUPER + SHIFT + M"]
    property bool premium: false
    property bool hasTrack: true
    property bool isPlaying: true
    property bool isAd: false
    property bool adSkippable: false
    property bool panelOpen: false
    property string lastError: ""
    property var engine: ({ status: "ready", error: "", signedIn: true, host: "music.youtube.com", wantRunning: true })
    property var account: ({ signedIn: true, host: "music.youtube.com" })
    property var player: ({ videoId: "AAAAAAAAAAA", title: "Northern Lights", artists: [{ name: "The Examples" }], playing: true, volume: 70, duration: 200, position: 42 })
    property string videoId: "AAAAAAAAAAA"
    property string title: "Northern Lights"
    property string artist: "The Examples"
    property string album: ""
    property string thumb: ""
    property real duration: 200
    property real position: 42
    property int volume: 70
    property bool muted: false
    property string repeatMode: "NONE"
    property string like: "INDIFFERENT"
    property int fastClockUsers: 0
    property string engineLine: "Playing"
    property var settings: ({
      barControls: true, showTitle: true, maxLabelWidth: 160, showWhenIdle: true, notify: true,
      globalKeys: true, autostart: true, browser: "",
      eqEnabled: false, eqPreset: "flat", eqBands: "[0,0,0,0,0,0,0,0,0,0]", eqPreamp: 0, eqLoudness: false,
      startPaused: false, startVolume: "last", recycleHeapMb: 400, recycleHours: 12
    })
    function setting(name, fallback) {
      var v = settings ? settings[name] : undefined
      return v === undefined || v === null ? fallback : v
    }
    function saveSetting(key, value) { var n = Object.assign({}, settings); n[key] = value; settings = n }
    function resetSettings() {}
    property string sleepMode: "off"
    function nudgeSleepMode(dir) { sleepMode = Model.nextSleepOption(sleepMode, dir) }
    property string solfaVersion: "0.1.0-fixture"
    function engineVersion(cb) { if (cb) cb({ ok: true, data: { product: "FakeChrome/999.0 (fixture)" } }) }
    function clearCache(cb) { if (cb) cb({ ok: true, data: {} }) }
    function eraseProfile(cb) { if (cb) cb({ ok: true, data: {} }) }
    property var accountDetails: ({ name: "Alex Example", email: "alex@example.com", avatar: "" })
    function accountInfo(cb) { if (cb) cb({ ok: true, data: accountDetails }) }
    function accountSwitch(cb) { if (cb) cb({ ok: true, data: {} }) }
    function accountSignOut(cb) { if (cb) cb({ ok: true, data: {} }) }
    // Everything a view may call: recorded, never acted on.
    property var calls: []
    function request(op, args, cb) {
      calls.push(op)
      // SOLFA_SCENE_OUT0 (the parity render) wants a queue to draw; the
      // other runs keep the old "not found".
      if (op === "queue" && cb && Quickshell.env("SOLFA_SCENE_OUT0")) {
        var names = [["Northern Lights", "The Examples"], ["Paper Lanterns", "The Quiet Meridian"], ["Static Bloom", "Orla Vance"], ["Seventeen Windows", "Kite & Compass"], ["Slow Neon", "Hollow Parade"]]
        cb({ ok: true, data: { index: 0, items: names.map(function (n, i) { return { videoId: "ID" + i, title: n[0], artists: [{ name: n[1] }], duration: 200 + i * 17, kind: "song" } }) } })
        return 0
      }
      if (cb) cb({ ok: false, error: "not-found" })
      return 0
    }
    function report(code) {}
    function startEngine() { calls.push("startEngine") }
    function restartEngine() {}
    function toggleEngine() {}
    function togglePlaying() {}
    function next() {}
    function previous() {}
    function seek(s) {}
    function seekBy(d) {}
    function setVolume(v) {}
    function nudgeVolume(s) {}
    function toggleMute() {}
    function toggleLike() {}
    function dislike() {}
    function cycleRepeat() {}
    function shuffle() {}
    function skipAd() {}
    function signIn() { calls.push("signIn") }
    function showWindow() { calls.push("showWindow") }
    function hideWindow() { calls.push("hideWindow") }
    function playItem(item, cb) {}
    function radioFor(item) {}
    function enqueue(item, next, cb) {}
  }


  // The panel as it is when Solfa is off.
  function turnOff() {
    fakeSvc.hasTrack = false; fakeSvc.isPlaying = false; fakeSvc.ready = false
    fakeSvc.player = null; fakeSvc.videoId = ""; fakeSvc.title = ""; fakeSvc.artist = ""; fakeSvc.position = 0; fakeSvc.duration = 0
    fakeSvc.engine = { status: "stopped", error: "", signedIn: true, host: "", wantRunning: false }
    fakeSvc.closed = true; fakeSvc.engineLine = Model.engineLine(fakeSvc.engine, fakeSvc.account)
  }

  FloatingWindow {
    id: barWin
    implicitWidth: 220
    implicitHeight: 34
    visible: true
    color: "transparent"
    // After: the box is exactly as wide as the widget, so the PNG's edges are the bar notch's edges.
    Rectangle { id: barBox; anchors.centerIn: parent; height: parent.height; width: scene.before ? parent.width : Math.round(bar.implicitWidth); color: Color.bar ? Color.bar.background : "#101014"
      SolfaBar { id: bar; bar: shotBar; anchors.centerIn: parent } }
    TestCase { id: barTc; name: "shots-bar"; when: false }
  }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 900
    visible: true
    color: "transparent"
    Item { id: stage; anchors.fill: parent
      SolfaPanel { id: panel; svc: fakeSvc } }
    TestCase { id: tc; name: "shots-panel"; when: false }
  }

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var f = find(item.children[i], name); if (f) return f }
    return null
  }

  // One step at a time: wait for the screen to settle, then run it. A grab calls next() when saved.
  property var steps: []
  property int at: 0
  Timer { id: settle; interval: 2000; onTriggered: scene.steps[scene.at++]() }
  function next() { if (scene.at < scene.steps.length) settle.restart(); else Qt.quit() }
  function save(item, name) {
    item.grabToImage(function (r) {
      r.saveToFile(Quickshell.env("SOLFA_SHOT_OUT") + "/" + name)
      console.log("SHOT " + name)
      scene.next()
    })
  }
  function card() { return find(stage, "panelCard") }

  Component.onCompleted: {
    turnOff()
    var beforeSteps = [
      function () { save(barBox, "before-bar.png") },
      function () { panel.open(); next() },
      function () { save(card(), "before-panel.png") }
    ]
    var afterSteps = [
      function () { save(barBox, "after-bar-rest.png") },
      function () { barTc.mouseMove(bar, 1, 1); barTc.mouseMove(bar, bar.pillBoxX + bar.pillBoxW / 2, bar.height / 2); next() },
      function () { save(barBox, "after-bar-hover.png") },
      function () { panel.open(); next() },
      function () { save(card(), "after-panel-rest.png") },
      function () { var cv = find(stage, "offCover"); tc.mouseMove(cv, 1, 1); tc.mouseMove(cv, cv.width / 2, cv.height / 2); next() },
      function () { save(card(), "after-panel-hover.png") },
      function () { tc.mouseMove(stage, 1, 1); fakeSvc.lastTitle = ""; fakeSvc.lastThumb = ""; next() },
      function () { save(card(), "after-panel-no-song.png") },
      function () { fakeSvc.signedIn = false; fakeSvc.account = { signedIn: false, host: "" }; next() },
      function () { save(card(), "after-panel-first-run-signed-out.png") },
      // Play on pressed: the engine starts and brings the song back; the hero shows it, loading.
      function () {
        fakeSvc.signedIn = true; fakeSvc.account = { signedIn: true, host: "music.youtube.com" }
        fakeSvc.lastTitle = "Glass Harbour"; fakeSvc.lastThumb = "file://" + Quickshell.env("SOLFA_SHOT_COVER")
        fakeSvc.engine = { status: "starting", error: "", signedIn: true, host: "", wantRunning: true }
        fakeSvc.closed = false; fakeSvc.starting = true; fakeSvc.engineLine = ""
        next()
      },
      function () { save(card(), "after-panel-starting.png") }
    ]
    steps = before ? beforeSteps : afterSteps
    next()
  }
  Timer { interval: 60000; running: true; onTriggered: Qt.quit() }
}
