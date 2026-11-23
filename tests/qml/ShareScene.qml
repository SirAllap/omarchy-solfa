import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml and its "Copy link" button and key (test_share_link.py):
// c and the button in Now Playing ask the service to copy the playing song's
// link and the footer says "Link copied"; with no song, or an advert, the
// button is gone and the key says there is nothing to share. Every step is
// read back from the live items and logged as one "STATE {...}" line; the
// card is saved to SOLFA_SCENE_OUT when set. The service is fake: it records
// the copyLink calls and answers them.
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
    // The save picker's three operations answer here; `failOps` makes one fail.
    property var log: []
    property var failOps: ({})
    property var playlists: [
      { id: "PLfixtureRoad", title: "Road trip", count: "889 tracks", recent: true },
      { id: "PLfixtureStudy", title: "Study", count: "13 tracks", recent: true },
      { id: "PLfixtureShared", title: "Shared mix", count: "6 tracks", recent: false },
      { id: "LM", title: "Liked Music", count: "206 songs", recent: false }
    ]
    // Playlists that refuse a song unless it is forced (the check says duplicate).
    property var dupIds: ["PLfixtureStudy"]
    // The share link: what the panel asks of the service, recorded.
    property var copied: []
    property string copyAnswer: "https://music.youtube.com/watch?v=AAAAAAAAAAA"
    function copyLink(cb) { copied.push(videoId); if (cb) cb(copyAnswer, "share-panel") }
    function request(op, args, cb) {
      calls.push(op)
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (failOps[op]) reply = { ok: false, error: failOps[op] }
      else if (op === "playlist.options") reply = { ok: true, data: { playlists: playlists } }
      else if (op === "playlist.add") reply = { ok: true, data: dupIds.indexOf(args.playlistId) !== -1 && !args.force ? { added: false, duplicate: true } : { added: true } }
      else if (op === "playlist.create") reply = { ok: true, data: { playlistId: "PLnewfixture" } }
      if (cb) cb(reply)
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

    TestCase { id: tc; name: "share-link"; when: false }

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
    function key(k, t) { panel.onKey({ key: k, text: t, modifiers: 0, accepted: false }) }

    Timer { id: settle; interval: 200; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var st = {}
          var button = win.find(stage, "shareButton")
          st.button = { shown: win.shown("shareButton"), enabled: button.enabled, tip: button.tooltipText }
          st.hint = Model.ALL_KEY_HINTS.filter(function (h) { return h[0] === "c" }).map(function (h) { return h[1] })
          var out = Quickshell.env("SOLFA_SCENE_OUT")
          var next = function () {
            // c: copies, and says so.
            win.key(Qt.Key_C, "c")
            st.key = { copied: fakeSvc.copied.slice(), flash: panel.flash }
            panel.flash = ""
            // The button does the same.
            button.clicked()
            st.click = { copied: fakeSvc.copied.slice(), flash: panel.flash }
            panel.flash = ""
            // The service could not make a link: nothing was copied, and it says so.
            fakeSvc.copyAnswer = ""
            win.key(Qt.Key_C, "c")
            st.failed = { flash: panel.flash }
            panel.flash = ""
            fakeSvc.copyAnswer = "https://music.youtube.com/watch?v=AAAAAAAAAAA"
            // An advert is playing: its link is not the song's.
            fakeSvc.isAd = true
            var before = fakeSvc.copied.length
            win.key(Qt.Key_C, "c")
            st.ad = { shown: win.shown("shareButton"), flash: panel.flash, asked: fakeSvc.copied.length - before }
            panel.flash = ""
            fakeSvc.isAd = false
            // Nothing loaded: the button is gone, the key says why.
            fakeSvc.hasTrack = false
            win.after(function () {
              before = fakeSvc.copied.length
              win.key(Qt.Key_C, "c")
              st.none = { shown: win.shown("shareButton"), flash: panel.flash, asked: fakeSvc.copied.length - before }
              panel.flash = ""
              fakeSvc.hasTrack = true
              // In the search field the letter types: it is not a shortcut there.
              panel.showTab("search")
              win.after(function () {
                var field = win.find(stage, "searchField")
                field.forceActiveFocus()
                before = fakeSvc.copied.length
                win.key(Qt.Key_C, "c")
                st.inField = { asked: fakeSvc.copied.length - before, flash: panel.flash }
                console.log("STATE " + JSON.stringify(st))
                Qt.quit()
              })
            })
          }
          if (out) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(out); next() })
          else next()
        })
      }
    }
  }
}
