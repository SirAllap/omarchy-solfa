import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml (test_panel_settings.py) with Settings opened from it:
// Settings must replace the whole body (no hero, no transport, no tabs) and
// its "‹ Settings" back row must sit on the top row, level with the brand
// corner. The shell's KeyboardPanel is swapped for tests/qml/stub (a plain
// card: no layer-shell window, no keyboard grab). Logs one "STATE {...}"
// line; saves the settings-open frame to SOLFA_SCENE_OUT when set.
ShellRoot {
  id: scene

  QtObject {
    id: fakeSvc
    property bool bridgeUp: true
    property bool ready: true
    property bool signingIn: false
    property bool gated: false
    property bool closed: false
    property bool signedIn: true
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

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 720
    visible: true
    color: "transparent"

    Item {
      id: stage
      anchors.fill: parent
      SolfaPanel {
        id: panel
        svc: fakeSvc
      }
    }

    TestCase { id: tc; name: "panel-open-close"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function shown(name) {
      var it = find(stage, name)
      if (!it) return null
      for (var p = it; p; p = p.parent) if (!p.visible) return false
      return true
    }
    function snap() {
      var q = find(stage, "queueView")
      return {
        opened: panel.opened,
        card: shown("panelCard"),
        queue: shown("queueView"),
        skeleton: shown("queueLoading"),
        loading: q ? q.loading : null,
        active: q ? q.active : null,
        opacity: q ? q.opacity : null
      }
    }

    Timer { id: settle; interval: 600; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var open1 = win.snap()
          panel.close()
          win.after(function () {
            var closed1 = win.snap()
            panel.open()
            win.after(function () {
              var open2 = win.snap()
              panel.close()
              win.after(function () {
                console.log("STATE " + JSON.stringify({ open1: open1, closed1: closed1, open2: open2, closed2: win.snap() }))
                Qt.quit()
              })
            })
          })
        })
      }
    }
  }
}
