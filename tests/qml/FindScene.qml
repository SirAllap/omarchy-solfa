import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml on a playlist page with "Find in playlist"
// (test_find_in_playlist.py): F or the button opens a field, typing filters,
// the rest of the playlist is fetched page after page, Enter and the row
// buttons act on the song that was filtered to, Esc steps back. Every step is
// read back from the live items and logged as one "STATE {...}" line. The
// service is fake: it records the requests and answers `browse` from
// invented pages, holding the continuation ones until the scene lets them go.
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
    function page(args) {
      var tok = args.continuation || ""
      if (args.id === "PLfixtureBig") {
        if (!tok) return { kind: "playlist", title: "Big mix", author: "Alex Example", playlistId: "PLfixtureBig", tracks: range(0, 100, "V"), continuation: "tokB1" }
        if (tok === "tokB1") return { tracks: range(100, 200, "V"), continuation: "tokB2" }
        if (tok === "tokB2") return { tracks: range(200, 250, "V"), continuation: "" }
      }
      if (args.id === "PLfixtureFlaky") {
        if (!tok) return { kind: "playlist", title: "Flaky mix", playlistId: "PLfixtureFlaky", tracks: range(0, 100, "F"), continuation: "tokF1" }
        if (tok === "tokF1") return { tracks: range(100, 200, "F"), continuation: "tokF2" }
        return null
      }
      if (args.id === "MPREbfixture") return { kind: "album", title: "Small album", artists: [{ name: "The Examples" }], playlistId: "OLAK5uyfixture", tracks: range(0, 5, "A") }
      if (args.id === "UCfixtureArtist") return { kind: "artist", title: "An Artist", sections: [{ title: "Songs", items: range(0, 3, "R") }] }
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

    TestCase { id: tc; name: "find-in-playlist"; when: false }

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
          var button = win.find(stage, "findButton")

          // ---- a playlist page: the button is there, f is still "like"
          panel.openPage({ browseId: "PLfixtureBig", title: "Big mix" })
          st.page = { pages: panel.pages.length, button: win.shown("findButton"), tooltip: button.tooltipText,
                      field: win.shown("findField"), rows: dv.rows.length, finding: dv.finding, hints: dv.hints,
                      asked: win.asked() }
          win.key(Qt.Key_F, "f")
          st.lowerF = { likes: fakeSvc.calls.filter(function (c) { return c === "toggleLike" }).length, finding: dv.finding }

          // ---- F opens the field, which has the focus; the rest of the pages come one at a time
          fakeSvc.hold = true
          var ev = win.key(Qt.Key_F, "F")
          st.byKey = { accepted: ev.accepted, finding: dv.finding, field: win.shown("findField"), focus: field.activeFocus,
                       inputFocused: dv.inputFocused, loadingAll: dv.loadingAll, pending: fakeSvc.pending.length,
                       rows: dv.rows.length, status: status.text, hints: dv.hints }
          // Letters typed into the field are not the panel's shortcuts.
          win.key(Qt.Key_N, "n")
          win.key(Qt.Key_Slash, "/")
          win.key(Qt.Key_F, "f")
          st.noShortcuts = { next: fakeSvc.calls.indexOf("next") === -1, likes: fakeSvc.calls.filter(function (c) { return c === "toggleLike" }).length,
                             pages: panel.pages.length, tab: panel.tab, focus: field.activeFocus }
          // Typed while only the first page is here.
          win.type("zoe")
          st.firstPageOnly = { titles: win.titles(dv), status: status.text }
          win.release(1)
          st.afterFirst = { titles: win.titles(dv), status: status.text, loaded: dv.info.tracks.length, pending: fakeSvc.pending.length, asked: win.asked() }
          win.release(1)
          st.afterSecond = { titles: win.titles(dv), status: status.text, loaded: dv.info.tracks.length, pending: fakeSvc.pending.length,
                             asked: win.asked(), loadingAll: dv.loadingAll, continuation: dv.info.continuation }
          fakeSvc.hold = false

          // ---- the filter itself
          var q = {}
          var queries = ["zoe", "ZOË", "creme", "CRÈME Brulee", "brulee zoe", "zoe brulee", "sessions", "samples sunrise", "zebra", "zoe zebra", "nothing at all", "song 15", "  "]
          queries.forEach(function (text) { win.type(text); q[text] = { titles: win.titles(dv), status: status.text, empty: list.emptyText } })
          st.queries = q
          st.pageIsKept = { tracks: dv.info.tracks.length, pageInfo: dv.page.info.tracks.length }

          // ---- the list: Enter in the field, Down, Enter, click, buttons, keys
          win.type("zoe")
          st.beforeList = { titles: win.titles(dv), cursor: dv.cursor }
          field.accepted()
          st.toList = { cursor: dv.cursor, fieldFocus: field.activeFocus, inputFocused: dv.inputFocused, finding: dv.finding, hints: dv.hints, current: dv.current.item.title }
          win.key(Qt.Key_Down, "")
          st.afterDown = { cursor: dv.cursor, current: dv.current.item.title }
          win.key(Qt.Key_Return, "")
          st.enter = { play: win.lastCall("play"), flash: panel.flash }
          list.activated(0)
          st.click = { play: win.lastCall("play") }
          win.key(Qt.Key_E, "e")
          st.playNext = fakeSvc.enqueued
          list.action("save", 1)
          st.saveButton = { open: panel.saveOpen, item: panel.saveItem }
          win.key(Qt.Key_Escape, "")
          st.saveEsc = { open: panel.saveOpen, finding: dv.finding, pages: panel.pages.length }
          dv.cursor = 0
          win.key(Qt.Key_S, "S")
          st.saveKey = { open: panel.saveOpen, item: panel.saveItem }
          win.key(Qt.Key_Escape, "")
          // Play and Shuffle are about the whole playlist, whatever the field holds.
          dv.playAll(false)
          st.playAll = win.lastCall("play")
          dv.playAll(true)
          st.shuffleAll = win.lastCall("play")

          // ---- Esc from the list closes the filter (not the page), on the same song
          dv.cursor = 1
          win.key(Qt.Key_Escape, "")
          st.escList = { finding: dv.finding, pages: panel.pages.length, rows: dv.rows.length, cursor: dv.cursor,
                         current: dv.current.item.title, query: dv.query, field: win.shown("findField"), hints: dv.hints }

          // ---- the button opens it, and F from the list goes back to the field
          button.clicked()
          st.byButton = { finding: dv.finding, focus: field.activeFocus, field: win.shown("findField"), loadingAll: dv.loadingAll }
          win.type("zoe")
          field.accepted()
          var fromList = win.key(Qt.Key_F, "F")
          st.fFromList = { accepted: fromList.accepted, inputFocused: dv.inputFocused, finding: dv.finding, text: field.text }

          // ---- Esc in the field: the text first, then the field, then the page
          win.fieldKey(Qt.Key_Escape)
          st.escField1 = { text: field.text, query: dv.query, finding: dv.finding, focus: field.activeFocus, rows: dv.rows.length, pages: panel.pages.length }
          win.fieldKey(Qt.Key_Escape)
          st.escField2 = { finding: dv.finding, inputFocused: dv.inputFocused, pages: panel.pages.length, field: win.shown("findField") }
          win.key(Qt.Key_Escape, "")
          st.escField3 = { pages: panel.pages.length }

          // ---- leaving while it loads: nothing more is asked, a late answer is dropped
          fakeSvc.hold = true
          panel.openPage({ browseId: "PLfixtureBig", title: "Big mix" })
          win.key(Qt.Key_F, "F")
          var before = win.asked().length
          st.loading = { pending: fakeSvc.pending.length, loadingAll: dv.loadingAll, status: status.text }
          panel.back()
          win.releaseAll()
          st.closedWhileLoading = { tracks: dv.info.tracks.length, asked: win.asked().length - before, pending: fakeSvc.pending.length,
                                    loadingAll: dv.loadingAll, finding: dv.finding, pages: panel.pages.length }
          // ... or moving to another page: the late answer does not touch it.
          panel.openPage({ browseId: "PLfixtureBig", title: "Big mix" })
          win.key(Qt.Key_F, "F")
          before = win.asked().length
          panel.openPage({ browseId: "MPREbfixture", title: "Small album" })
          win.releaseAll()
          st.otherPage = { title: dv.info.title, tracks: dv.info.tracks.length, asked: win.asked().length - before, finding: dv.finding, loadingAll: dv.loadingAll }
          panel.back()
          panel.back()
          st.openAgainInfo = { pages: panel.pages.length }
          fakeSvc.hold = false

          // ---- a page that fails: what came stays, and the filter works on it
          panel.openPage({ browseId: "PLfixtureFlaky", title: "Flaky mix" })
          win.key(Qt.Key_F, "F")
          st.flaky = { tracks: dv.info.tracks.length, loadingAll: dv.loadingAll, error: dv.loadError, flash: panel.flash,
                       status: status.text, continuation: dv.info.continuation, finding: dv.finding }
          win.type("song 15")
          st.flakyFilter = { count: dv.rows.length, status: status.text }
          panel.back()

          // ---- an album says so; an artist page has no find
          panel.openPage({ browseId: "MPREbfixture", title: "Small album" })
          st.album = { tooltip: button.tooltipText, button: win.shown("findButton") }
          win.key(Qt.Key_F, "F")
          st.albumFind = { finding: dv.finding, placeholder: field.placeholderText, requests: win.asked().length }
          win.type("song 3")
          st.albumFilter = { titles: win.titles(dv), status: status.text }
          panel.back()
          panel.openPage({ browseId: "UCfixtureArtist", title: "An Artist" })
          var onArtist = win.key(Qt.Key_F, "F")
          st.artist = { button: win.shown("findButton"), finding: dv.finding, accepted: onArtist.accepted, hints: dv.hints }
          console.log("STATE " + JSON.stringify(st))
          Qt.quit()
        })
      }
    }
  }
}
