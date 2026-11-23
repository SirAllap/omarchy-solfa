import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Design check (not a test): the real BarWidget.qml pill on every bar look the shell has
// (opaque, glassy = "translucent", none = "transparent") over a pink wallpaper stub, at rest,
// hovered and open. Rendered offscreen by tests/bar_states.py. Env: SOLFA_THEME (light|dark),
// SOLFA_MODE (opaque|glassy|none), SOLFA_COVER (a picture), SOLFA_OUT_DIR. The bar is painted the
// way plugins/bar/Bar.qml:1838 paints it. Logs one "STATES {...}" line with the colours each
// state paints, for the contrast numbers.
ShellRoot {
  id: scene
  readonly property string mode: Quickshell.env("SOLFA_MODE") || "opaque"
  readonly property string theme: Quickshell.env("SOLFA_THEME") || "dark"
  readonly property string tag: mode === "glassy" ? "translucent" : mode === "none" ? "transparent" : "opaque"

  QtObject {
    id: svc
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: true
    property bool hasTrack: true
    property bool isPlaying: true
    property bool isAd: false
    property bool signedIn: true
    property bool premium: false
    property bool gated: false
    property bool panelOpen: false
    property string lastError: ""
    property var engine: ({ status: "ready", error: "", signedIn: true, host: "music.youtube.com", wantRunning: true })
    property var account: ({ signedIn: true, host: "music.youtube.com" })
    property var player: ({ videoId: "AAAAAAAAAAA", title: "Reise, Reise", artists: [{ name: "The Examples" }], playing: true, volume: 60, duration: 214, position: 83 })
    property string videoId: "AAAAAAAAAAA"
    property string title: "Reise, Reise"
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: ""
    property string thumb: Quickshell.env("SOLFA_COVER")
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property int volume: 60
    property bool muted: false
    property string repeatMode: "NONE"
    property string like: "INDIFFERENT"
    property var settings: ({})
    property int fastClockUsers: 0
    function setting(name, fallback) { return fallback }
    function request(op, args, cb) { if (cb) cb({ ok: false, error: "not-found" }); return 0 }
    function report(code) {}
    function startEngine() {}
    function togglePlaying() {}
    function previous() {}
    function next() {}
    function seekBy(d) {}
    function nudgeVolume(s) {}
  }
  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property bool transparent: scene.mode === "none"
    property color barForeground: Commons.Color.bar.text
    property color background: Commons.Color.bar.background
    property string fontFamily: Style.font.family
    property var shell: QtObject {
      property var barConfig: ({ background: scene.mode })
      function serviceFor(id) { return svc }
    }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 260
    implicitHeight: 26
    visible: true
    color: "transparent"

    // The wallpaper stub: pink, light on the left, deep on the right, so the pill meets both.
    Item {
      id: stage
      anchors.fill: parent
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#f4a6c4" }
          GradientStop { position: 0.5; color: "#e8709f" }
          GradientStop { position: 1.0; color: "#c2467a" }
        }
      }
      // Bar.qml:1838 - transparent wins, glassy uses glassBackground (alpha <= 0.35).
      Rectangle {
        anchors.fill: parent
        color: fakeBar.transparent ? "transparent"
          : scene.mode === "glassy" ? Qt.rgba(fakeBar.background.r, fakeBar.background.g, fakeBar.background.b, Math.min(fakeBar.background.a, 0.35))
          : fakeBar.background
      }
      // The widget's own settings entry, as the shell hands it over: SOLFA_BAR_FLAT=1 sets barFlat
      // on, =0 sets it off, and unset leaves the entry without it (the default).
      SolfaBar {
        id: w; bar: fakeBar; anchors.centerIn: parent
        settings: Quickshell.env("SOLFA_BAR_FLAT") === "1" ? ({ barFlat: true })
          : Quickshell.env("SOLFA_BAR_FLAT") === "0" ? ({ barFlat: false }) : ({ showTitle: true })
      }
    }

    TestCase { id: tc; name: "bar-states"; when: false }

    property var info: ({})
    property var order: ["rest", "hover", "open"]
    property int step: 0

    function snap(state) {
      var f = w.pillFill, ink = w.fg, b = w.barBg
      info[state] = {
        fill: [f.r, f.g, f.b, f.a], ink: [ink.r, ink.g, ink.b, ink.a], bar: [b.r, b.g, b.b, b.a],
        paintAlpha: fakeBar.transparent ? 0 : scene.mode === "glassy" ? Math.min(b.a, 0.35) : b.a,
        hot: w.pillHot, opened: w.opened,
        family: w.family, barFamily: fakeBar.fontFamily, barInk: [fakeBar.barForeground.r, fakeBar.barForeground.g, fakeBar.barForeground.b, fakeBar.barForeground.a],
        width: Math.round(w.implicitWidth), outlined: w.pillOutlined, flat: w.barFlat
      }
    }
    function go() {
      var state = order[step]
      if (state === "hover") tc.mouseMove(w, w.width / 2, w.height / 2)
      if (state === "open") { tc.mouseMove(stage, 2, 2); w.open() }
      Qt.callLater(function () { settle.restart() })
    }
    Timer {
      id: settle
      interval: 500
      onTriggered: {
        var state = win.order[win.step]
        win.snap(state)
        stage.grabToImage(function (r) {
          r.saveToFile(Quickshell.env("SOLFA_OUT_DIR") + "/bar-" + scene.theme + "-" + scene.tag + "-" + state + ".png")
          if (++win.step < win.order.length) win.go()
          else { console.log("STATES " + JSON.stringify(win.info)); Qt.quit() }
        })
      }
    }
    Timer { interval: 1200; running: true; onTriggered: win.go() }
  }
}
