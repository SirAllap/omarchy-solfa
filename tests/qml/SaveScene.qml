import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml with its "Save to playlist" picker (test_save_picker.py):
// S opens it for the playing song, typing filters, Enter saves, "New
// playlist" names one, a signed-out panel says so. Every step is read back
// from the live items and logged as one "STATE {...}" line; the picker is
// saved to SOLFA_SCENE_OUT when set. The service is fake: it records the
// requests and answers the three playlist operations.
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

    TestCase { id: tc; name: "save-picker"; when: false }

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
    function type(text) {
      var field = find(stage, "saveField")
      field.text = text
      field.textEdited()
    }
    function lastCall(op) {
      for (var i = fakeSvc.log.length - 1; i >= 0; i--) if (fakeSvc.log[i].op === op) return fakeSvc.log[i].args
      return null
    }
    function count(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).length }
    function names(rows) { return rows.map(function (r) { return r.create ? "+" : r.header ? "#" + r.header : r.playlist.title }) }

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
          var view = win.find(stage, "saveView")
          st.actions = {
            song: panel.itemActions({ item: { kind: "song", videoId: "BBBBBBBBBBB" } }).map(function (a) { return a.name }),
            video: panel.itemActions({ item: { kind: "video", videoId: "CCCCCCCCCCC" } }).map(function (a) { return a.name }),
            album: panel.itemActions({ item: { kind: "album", browseId: "MPREb_x", playlistId: "OLAK5uy_x" } }).map(function (a) { return a.name }),
            queue: win.find(stage, "queueView").actionsFor({ item: { videoId: "DDDDDDDDDDD" }, queueIndex: 1 }).map(function (a) { return a.name }),
            queueAutomix: win.find(stage, "queueView").actionsFor({ item: { videoId: "DDDDDDDDDDD" }, automix: true }).map(function (a) { return a.name })
          }
          st.heroButton = win.shown("saveButton")
          st.closedAtStart = win.shown("saveView")

          // S: the picker, for the playing song, with the list asked for.
          win.key(Qt.Key_S, "S")
          win.after(function () {
            st.open = { shown: win.shown("saveView"), hints: win.shown("saveHints"), item: panel.saveItem,
                        asked: win.lastCall("playlist.options"), rows: win.names(view.rows), cursor: view.cursor,
                        counts: view.rows.map(function (r) { return r.playlist ? r.playlist.count : "" }) }
            var out = Quickshell.env("SOLFA_SCENE_OUT")
            var next = function () {
              // Typing filters; case does not matter; "New playlist" stays.
              win.type("sTU")
              st.filtered = { rows: win.names(view.rows), cursor: view.cursor }
              win.type("zzz")
              st.nothing = { rows: win.names(view.rows), text: view.emptyText }
              win.type("")
              // Down moves, Up moves back.
              view.move(1); view.move(1)
              st.moved = view.cursor
              view.move(-1)
              // Enter on "Road trip" (the first row to rest on): saved, picker closed, message.
              view.cursor = 2
              view.accept()
              win.after(function () {
                st.saved = { add: win.lastCall("playlist.add"), open: panel.saveOpen, flash: panel.flash, shown: win.shown("saveView") }
                // A playlist that has it already: refused once, the footer says so,
                // and Enter again on the same row adds it anyway.
                win.key(Qt.Key_S, "S")
                win.after(function () {
                  view.cursor = 3
                  view.accept()
                  st.already = { flash: panel.flash, open: panel.saveOpen, dupId: view.dupId, hint: win.shown("saveHints"), args: win.lastCall("playlist.add") }
                  view.move(1)
                  st.dupAfterMove = view.dupId
                  view.move(-1)
                  view.accept()
                  var sent = win.count("playlist.add")
                  view.accept()
                  st.anyway = { args: win.lastCall("playlist.add"), flash: panel.flash, open: panel.saveOpen, sent: win.count("playlist.add") - sent }
                  // New playlist: name it, create with the song.
                  win.key(Qt.Key_S, "S")
                  win.after(function () {
                    view.cursor = 0
                    view.accept()
                    st.naming = { creating: view.creating, text: win.find(stage, "saveField").text, listShown: win.shown("saveList") }
                    // Esc steps back from naming to the list, not out.
                    win.key(Qt.Key_Escape, "")
                    st.escFromNaming = { creating: view.creating, open: panel.saveOpen }
                    view.cursor = 0
                    view.accept()
                    win.type("  ")
                    view.accept()
                    st.emptyName = { creating: view.creating, flash: panel.flash, created: win.count("playlist.create") }
                    win.type("Fresh mix")
                    view.accept()
                    win.after(function () {
                      st.created = { args: win.lastCall("playlist.create"), flash: panel.flash, open: panel.saveOpen }
                      // A failure keeps the picker open and says why.
                      fakeSvc.failOps = { "playlist.add": "failed" }
                      win.key(Qt.Key_S, "S")
                      win.after(function () {
                        view.cursor = 2
                        view.accept()
                        st.failed = { flash: panel.flash, open: panel.saveOpen, busy: view.busy }
                        // Esc closes the picker.
                        win.key(Qt.Key_Escape, "")
                        st.escClosed = { open: panel.saveOpen, shown: win.shown("saveView") }
                        // Signed out: said, nothing asked.
                        fakeSvc.failOps = ({})
                        fakeSvc.signedIn = false
                        fakeSvc.account = { signedIn: false, host: "music.youtube.com" }
                        var asked = win.count("playlist.options")
                        win.key(Qt.Key_S, "S")
                        st.signedOut = { open: panel.saveOpen, flash: panel.flash, asked: win.count("playlist.options") - asked }
                        console.log("STATE " + JSON.stringify(st))
                        Qt.quit()
                      })
                    })
                  })
                })
              })
            }
            if (out) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(out); next() })
            else next()
          })
        })
      }
    }
  }
}
