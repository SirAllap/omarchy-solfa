import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml on a playlist of the user's own with the find field
// open (test_remove_while_finding.py): x, Delete and the row button take the
// filtered song out, the field keeps its own x and Delete, and a removal and
// the pages of the playlist that are still arriving do not undo each other.
// Every step is read back from the live items and logged as one "STATE {...}"
// line. The service is fake: it records the requests, answers `browse` from
// invented pages and holds continuation answers and removals until the scene
// lets them go.
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
    // Every request, in order, with its arguments.
    property var log: []
    property bool hold: false       // continuation answers wait in `pending`
    property var pending: []
    property var enqueued: []
    function track(n, prefix) {
      var id = prefix + ("0000000000" + n).slice(-10)
      var t = { videoId: id, setVideoId: "S" + id, title: "Song " + n, artists: [{ name: "Artist " + (n % 5) }], album: { name: "Album " + (n % 7) }, duration: 180 }
      if (prefix === "V" && n === 7) { t.title = "Crème Brûlée"; t.artists = [{ name: "Zoë Example" }]; t.album = { name: "Été Sessions" } }
      if (prefix === "V" && n === 130) { t.title = "Sunrise"; t.artists = [{ name: "Zoë Example" }, { name: "The Samples" }] }
      if (prefix === "V" && n === 230) t.title = "Zebra Crossing"
      return t
    }
    function range(from, to, prefix) {
      var out = []
      for (var i = from; i < to; i++) out.push(track(i, prefix))
      return out
    }
    property bool holdRemove: false  // playlist.remove answers wait in `pendingRemove`
    property var pendingRemove: []
    function page(args) {
      var tok = args.continuation || ""
      if (args.id === "PLfixtureMine") {
        if (!tok) return { kind: "playlist", title: "Mine mix", author: "Alex Example", playlistId: "PLfixtureMine", editable: true, tracks: range(0, 100, "V"), continuation: "tokB1" }
        if (tok === "tokB1") return { tracks: range(100, 200, "V"), continuation: "tokB2" }
        if (tok === "tokB2") return { tracks: range(200, 250, "V"), continuation: "" }
      }
      return null
    }
    function request(op, args, cb) {
      calls.push(op)
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (op === "browse") {
        var p = page(args)
        reply = p ? { ok: true, data: p } : { ok: false, error: "timeout" }
        if (args.continuation && hold && cb) { pending.push(function () { cb(reply) }); return 0 }
      } else if (op === "playlist.remove") {
        reply = { ok: true, data: { removed: true } }
        if (holdRemove && cb) { pendingRemove.push(function () { cb(reply) }); return 0 }
      } else if (op === "playlist.options") reply = { ok: true, data: { playlists: [] } }
      else if (op === "play") reply = { ok: true, data: {} }
      if (cb) cb(reply)
      return 0
    }
    function report(code) {}
    function startEngine() { calls.push("startEngine") }
    function restartEngine() {}
    function toggleEngine() {}
    function togglePlaying() {}
    function next() { calls.push("next") }
    function previous() {}
    function seek(s) {}
    function seekBy(d) {}
    function setVolume(v) {}
    function nudgeVolume(s) {}
    function toggleMute() {}
    function toggleLike() { calls.push("toggleLike") }
    function dislike() {}
    function cycleRepeat() {}
    function shuffle() {}
    function skipAd() {}
    function signIn() { calls.push("signIn") }
    function showWindow() { calls.push("showWindow") }
    function hideWindow() { calls.push("hideWindow") }
    function playItem(item, cb) {}
    function radioFor(item) {}
    function enqueue(item, next, cb) { enqueued.push({ videoId: item.videoId, next: next }) }
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

    TestCase { id: tc; name: "remove-while-finding"; when: false }

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
    function key(k, t) {
      var ev = { key: k, text: t, modifiers: 0, accepted: false }
      panel.onKey(ev)
      return ev
    }
    // What the field itself does with a key, as the real field sees it.
    function fieldKey(k) {
      tc.keyClick(k)
    }
    function type(text) {
      var field = find(stage, "findField")
      field.text = text
      field.textEdited()
    }
    function lastCall(op) {
      for (var i = fakeSvc.log.length - 1; i >= 0; i--) if (fakeSvc.log[i].op === op) return fakeSvc.log[i].args
      return null
    }
    function count(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).length }
    function asked() { return fakeSvc.log.filter(function (e) { return e.op === "browse" && e.args.continuation }).map(function (e) { return e.args.continuation }) }
    function release(n) { for (var i = 0; i < n && fakeSvc.pending.length; i++) fakeSvc.pending.shift()() }
    function releaseRemove() { if (fakeSvc.pendingRemove.length) fakeSvc.pendingRemove.shift()() }
    function removed() { return fakeSvc.log.filter(function (e) { return e.op === "playlist.remove" }).map(function (e) { return e.args.setVideoId }) }
    function releaseAll() { var n = 0; while (fakeSvc.pending.length && n++ < 50) fakeSvc.pending.shift()() }
    function titles(dv) { return dv.rows.map(function (r) { return r.item.title }) }
    function ids(dv) { return dv.rows.map(function (r) { return r.item.videoId }) }

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
          var dv = win.find(stage, "detailView")
          var field = win.find(stage, "findField")
          var list = win.find(stage, "detailList")
          var status = win.find(stage, "findStatus")

          // ---- all the pages loaded, a filter on: x takes out the song under the cursor
          panel.openPage({ browseId: "PLfixtureMine", title: "Mine mix" })
          fakeSvc.hold = true
          win.key(Qt.Key_F, "F")
          win.releaseAll()
          fakeSvc.hold = false
          win.type("zoe")
          field.accepted()
          st.beforeX = { titles: win.titles(dv), status: status.text, cursor: dv.cursor, hints: dv.hints, loaded: dv.info.tracks.length }
          var ev = win.key(Qt.Key_X, "x")
          st.afterX = { accepted: ev.accepted, removed: win.removed(), titles: win.titles(dv), status: status.text, cursor: dv.cursor,
                        loaded: dv.info.tracks.length, flash: panel.flash, finding: dv.finding, query: dv.query }

          // ---- a longer filtered list, the cursor on its second row: it stays on that place
          win.type("song 15")
          field.accepted()
          win.key(Qt.Key_Down, "")
          st.beforeMid = { titles: win.titles(dv), status: status.text, cursor: dv.cursor }
          win.key(Qt.Key_Delete, "")
          st.afterDelete = { removed: win.removed(), titles: win.titles(dv), status: status.text, cursor: dv.cursor, current: dv.current.item.title }
          // The row button, on the last row: the cursor falls back to the new last one.
          var last = dv.rows.length - 1
          dv.cursor = last
          list.action("remove", last)
          st.afterButton = { removed: win.removed(), count: dv.rows.length, status: status.text, cursor: dv.cursor }
          // What the page holds is the same list without those three songs.
          st.pageKept = { tracks: dv.info.tracks.length, pageInfo: dv.page.info.tracks.length }
          win.key(Qt.Key_Escape, "")
          st.closed = { finding: dv.finding, rows: dv.rows.length, gone: win.ids(dv).indexOf("V0000000007") === -1 }

          // ---- x and Delete in the field are keys of the field
          win.key(Qt.Key_F, "F")
          win.type("sun")
          var before = win.removed().length
          var kx = win.key(Qt.Key_X, "x")
          var kd = win.key(Qt.Key_Delete, "")
          field.cursorPosition = 0
          win.fieldKey(Qt.Key_Delete)
          st.inField = { removed: win.removed().length - before, accepted: [kx.accepted, kd.accepted], text: field.text, focus: field.activeFocus,
                         finding: dv.finding, rows: dv.rows.length }
          win.key(Qt.Key_Escape, "")
          win.key(Qt.Key_Escape, "")
          panel.back()

          // ---- a removal on its way while pages arrive: neither undoes the other
          fakeSvc.hold = true
          fakeSvc.holdRemove = true
          panel.openPage({ browseId: "PLfixtureMine", title: "Mine mix" })
          win.key(Qt.Key_F, "F")
          field.accepted()
          before = win.removed().length
          win.key(Qt.Key_X, "x")
          win.key(Qt.Key_X, "x")
          st.inFlight = { removed: win.removed().length - before, loaded: dv.info.tracks.length, rows: dv.rows.length, pendingPages: fakeSvc.pending.length }
          win.release(1)
          st.pageFirst = { loaded: dv.info.tracks.length, hasRow0: win.ids(dv).indexOf("V0000000000") !== -1, pendingPages: fakeSvc.pending.length }
          win.releaseRemove()
          st.thenRemoval = { loaded: dv.info.tracks.length, hasRow0: win.ids(dv).indexOf("V0000000000") !== -1, has150: win.ids(dv).indexOf("V0000000150") !== -1,
                             status: status.text, flash: panel.flash }
          win.releaseAll()
          fakeSvc.hold = false
          st.allPages = { loaded: dv.info.tracks.length, hasRow0: win.ids(dv).indexOf("V0000000000") !== -1, has249: win.ids(dv).indexOf("V0000000249") !== -1,
                          continuation: dv.info.continuation, status: status.text, loadingAll: dv.loadingAll, pageInfo: dv.page.info.tracks.length }
          fakeSvc.holdRemove = false
          panel.back()

          // ---- the other order: the removal is answered first, a page comes after it
          fakeSvc.hold = true
          panel.openPage({ browseId: "PLfixtureMine", title: "Mine mix" })
          win.key(Qt.Key_F, "F")
          field.accepted()
          win.key(Qt.Key_X, "x")
          st.removedFirst = { loaded: dv.info.tracks.length, pendingPages: fakeSvc.pending.length }
          win.releaseAll()
          fakeSvc.hold = false
          st.thenPages = { loaded: dv.info.tracks.length, hasRow0: win.ids(dv).indexOf("V0000000000") !== -1, has249: win.ids(dv).indexOf("V0000000249") !== -1,
                           status: status.text, pageInfo: dv.page.info.tracks.length }
          console.log("STATE " + JSON.stringify(st))
          Qt.quit()
        })
      }
    }
  }
}
