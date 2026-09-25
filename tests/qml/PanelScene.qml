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
    function request(op, args, cb) { calls.push(op); if (cb) cb({ ok: false, error: "not-found" }); return 0 }
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

    TestCase { id: tc; name: "panel-settings"; when: false }

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
    function topIn(name, ref) {
      var it = find(stage, name)
      return it ? Math.round(it.mapToItem(ref, 0, 0).y) : null
    }
    function midIn(name, ref) {
      var it = find(stage, name)
      return it ? Math.round(it.mapToItem(ref, 0, it.height / 2).y) : null
    }

    Timer { id: settle; interval: 250; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var card = win.find(stage, "panelCard")
          var closedState = { hero: win.shown("panelHero"), tabs: win.shown("panelTabs"), settings: win.shown("settingsView") }
          panel.toggleSettings()
          win.after(function () {
            var openState = {
              hero: win.shown("panelHero"), tabs: win.shown("panelTabs"), transport: win.shown("panelHero"),
              settings: win.shown("settingsView"), back: win.shown("settingsBack"), brand: win.shown("panelBrand"),
              backTop: win.topIn("settingsBack", card), backMid: win.midIn("settingsBack", card),
              brandTop: win.topIn("panelBrand", card), brandMid: win.midIn("panelBrand", card),
              heroBottom: win.find(stage, "panelHero") ? Math.round(win.find(stage, "panelHero").mapToItem(card, 0, win.find(stage, "panelHero").height).y) : null
            }
            var out = Quickshell.env("SOLFA_SCENE_OUT")
            var finish = function () {
              panel.onKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
              win.after(function () {
                var backState = { hero: win.shown("panelHero"), tabs: win.shown("panelTabs"), settings: win.shown("settingsView") }
                // Solfa turned off: only the way back on is shown.
                fakeSvc.hasTrack = false; fakeSvc.isPlaying = false; fakeSvc.ready = false
                fakeSvc.engine = { status: "stopped", error: "", signedIn: true, host: "", wantRunning: false }
                fakeSvc.closed = true; fakeSvc.engineLine = Model.engineLine(fakeSvc.engine, fakeSvc.account)
                win.after(function () {
                  var offState = { offCard: win.shown("offCard"), turnOn: win.shown("offTurnOn"), tabs: win.shown("panelTabs"),
                                   hero: win.shown("panelHero") }
                  panel.onKey({ key: Qt.Key_Return, text: "\r", modifiers: 0, accepted: false })
                  offState.startsAfterEnter = fakeSvc.calls.filter(function (c) { return c === "startEngine" }).length
                  // Signing in, signed out: the sign-in window may hand the
                  // keyboard back to the panel. Typing there must neither
                  // cancel the sign-in nor start another one.
                  fakeSvc.closed = false; fakeSvc.ready = true; fakeSvc.signedIn = false
                  fakeSvc.signingIn = true; fakeSvc.gated = true
                  fakeSvc.engine = { status: "signing-in", error: "", signedIn: false, host: "", wantRunning: true, signingIn: true }
                  var before = fakeSvc.calls.length
                  ;[{ key: Qt.Key_W, text: "W" }, { key: Qt.Key_W, text: "w" }, { key: Qt.Key_I, text: "i" },
                    { key: Qt.Key_Return, text: "\r" }, { key: Qt.Key_Space, text: " " }].forEach(function (e) {
                    panel.onKey({ key: e.key, text: e.text, modifiers: 0, accepted: false })
                  })
                  var signingState = { calls: fakeSvc.calls.slice(before) }
                  var done = function () {
                    console.log("STATE " + JSON.stringify({ closed: closedState, open: openState, afterEsc: backState, off: offState, signing: signingState }))
                    Qt.quit()
                  }
                  var out2 = Quickshell.env("SOLFA_SCENE_OUT2")
                  if (out2) card.grabToImage(function (r) { r.saveToFile(out2); done() })
                  else done()
                })
              })
            }
            if (out) card.grabToImage(function (r) { r.saveToFile(out); finish() })
            else finish()
          })
        })
      }
    }
  }
}
