import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml and a song with several artists (test_artist_pick.py):
// "Go to artist" (the button, g) opens the artist at once with one name and a small
// picker with several (Up/Down + Enter, a click, Esc or a click outside); the pointer on
// a row's title or artist text hides its buttons so every name shows and can be
// clicked. Every step is read back from the live items and logged as one "STATE {...}"
// line; SOLFA_SCENE_OUT gets the panel with a row hovered, SOLFA_PICKER_OUT the picker.
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
    property real adDuration: 15
    property real adPosition: 4
    property real adLeft: adDuration - adPosition
    property bool panelOpen: false
    property string lastError: ""
    property var engine: ({ status: "ready", error: "", signedIn: true, host: "music.youtube.com", wantRunning: true })
    property var account: ({ signedIn: true, host: "music.youtube.com" })
    // Nothing of the playlists playing at first.
    property var player: playing("ZZZZZZZZZZZ", "RDAMVMZZZZZZZZZZZ", "")
    property string videoId: player.videoId
    property string title: "One"
    property string artist: "The Examples"
    property string album: ""
    property string thumb: ""
    property real duration: 180
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
    property var log: []
    property var failOps: ({})
    // `hold`: playlist.remove is not answered until `held` is released.
    property bool hold: false
    property var held: []
    property var reported: []
    function playing(id, list, setId) {
      return { videoId: id, title: "One", artists: [{ name: "The Examples" }], playing: true, volume: 70, duration: 180, position: 42,
               ad: false, playlistId: list, setVideoId: setId, index: 0, canNext: true }
    }
    function song(id, title, artists) { return { kind: "song", videoId: id, title: title, artists: artists, duration: 180, setVideoId: "" } }
    function page(args) {
      if (args.id === "VLPLmulti" && !args.continuation)
        return { kind: "playlist", title: "Mix", subtitle: "3 songs", author: "Alex Example", thumb: "", playlistId: "PLmulti", editable: false, continuation: "",
          tracks: [
            song("MMMMMMMMMM1", "Rêverie du soir", [{ name: "berlioz", id: "UCa1" }, { name: "Ted Jasper", id: "UCa2" }, { name: "Third Artist" }]),
            song("MMMMMMMMMM2", "Solo song", [{ name: "Solo", id: "UCsolo" }]),
            song("MMMMMMMMMM3", "Long names", [{ name: "An artist with a very long name", id: "UCb1" }, { name: "Another artist with a long name", id: "UCb2" }, { name: "Last of the long names", id: "UCb3" }])
          ] }
      return null
    }
    // What playlist.restore answers: a new row each time, put back or not.
    property int restored: 0
    property bool placed: true
    function request(op, args, cb) {
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (failOps[op]) reply = { ok: false, error: failOps[op] }
      else if (op === "browse" && page(args)) reply = { ok: true, data: page(args) }
      else if (op === "queue") reply = { ok: true, data: { items: [], automix: [], index: 0, version: 1 } }
      else if (op === "playlist.remove" || op === "queue.removePlaying") reply = { ok: true, data: { removed: true } }
      else if (op === "playlist.restore") { restored++; reply = { ok: true, data: { setVideoId: "NEW" + restored, placed: placed } } }
      if (cb) cb(reply)
      return 0
    }
    function report(code) { reported.push(code) }
    function startEngine() { log.push({ op: "startEngine" }) }
    function restartEngine() {}
    function toggleEngine() {}
    // The song must keep playing: any of these would show in the log.
    function togglePlaying() { log.push({ op: "togglePlaying" }) }
    function next() { log.push({ op: "next" }) }
    function previous() { log.push({ op: "previous" }) }
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
    function signIn() {}
    function showWindow() {}
    function hideWindow() {}
    function playItem(item, cb) {}
    function radioFor(item) {}
    function enqueue(item, next, cb) {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 1000
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

    TestCase { id: tc; name: "undo-remove"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function key(k, t) { var e = { key: k, text: t, modifiers: 0, accepted: false }; panel.onKey(e); return e.accepted }
    function count(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).length }
    function sent(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).map(function (e) { return e.args }) }
    function sets(view) { return view.rows.map(function (r) { return r.item.setVideoId }) }
    function undoShown() { var b = win.find(stage, "undoButton"); return !!(b && b.visible) }
    // Offered at once (the notice fades in, so it is on screen a moment later).
    function undoOffered() { return !!panel.undoable && !panel.undoSent }
    // A click on the notice's Undo.
    function clickUndo() { var b = win.find(stage, "undoButton"); b.children[b.children.length - 1].clicked(null) }
    // x on the row with that setVideoId.
    function removeRow(view, set) {
      for (var i = 0; i < view.rows.length; i++) if (view.rows[i].item.setVideoId === set) view.cursor = i
      win.key(Qt.Key_X, "x")
    }
    function play(id, list, setId) { fakeSvc.player = fakeSvc.playing(id, list, setId) }

    Timer { id: settle; interval: 250; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }
    function findAny(item, test) {
      for (var i = 0; i < item.children.length; i++) {
        var c = item.children[i]
        if (test(c)) return c
        var f = win.findAny(c, test)
        if (f) return f
      }
      return null
    }
    function seq(steps) {
      var i = 0
      var next = function () { if (i < steps.length) { var f = steps[i++]; f(function () { win.after(next) }) } }
      next()
    }
    function names(p) { return p.artists.map(function (a) { return a.name }) }
    function lastPage() { return panel.pages.length ? panel.pages[panel.pages.length - 1] : { id: "", title: "" } }
    function grab(path, cb) { if (path) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(path); cb() }); else cb() }
    // The row's "Go to artist" button (hidden but present) and its artist links.
    function artistButton(row) { return win.findAny(row, function (c) { return c.tooltipText === "Go to artist (g)" }) }
    function link(row, n) { return win.findAny(row, function (c) { return c.objectName === "artistLink" + n }) }
    function rowItem(list, i) { return list.itemAtIndex(i) }
    function point(item, x, y) { return item.mapToItem(stage, x, y) }
    function moveOnto(item, x, y) {
      var p = win.point(item, x, y)
      tc.mouseMove(stage, 2, 2); tc.wait(150)
      for (var s = 4; s >= 0; s--) { tc.mouseMove(stage, p.x + s * 18, p.y); tc.wait(30) }
      tc.wait(200)
    }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var st = {}
          var out = Quickshell.env("SOLFA_SCENE_OUT")
          var outPicker = Quickshell.env("SOLFA_PICKER_OUT")
          panel.openPage({ browseId: "VLPLmulti", title: "Mix" })
          win.after(function () {
            var view = win.find(stage, "detailView")
            var list = win.find(stage, "detailList")
            var picker = win.find(stage, "artistPicker")
            st.rows = view.rows.length
            win.seq([
              // g on the 3-artist row: the picker lists all three; Down, Down, Enter opens the third (no id: a search).
              function (done) {
                view.cursor = 0
                win.key(0, "g")
                st.g = { shown: picker.shown, names: picker.artists.map(function (a) { return a.name }), pages: panel.pages.length }
                win.key(Qt.Key_Down, ""); win.key(Qt.Key_Down, "")
                st.g.cursor = picker.cursor
                win.key(Qt.Key_Return, "")
                st.g.afterEnter = { shown: picker.shown, search: win.sent("search"), pages: panel.pages.length }
                done()
              },
              // g, Down, Enter: the second, which has an id, opens its page.
              function (done) {
                win.key(0, "g"); win.key(Qt.Key_Down, ""); win.key(Qt.Key_Return, "")
                st.second = { shown: picker.shown, pages: panel.pages.length, id: win.lastPage().id, title: win.lastPage().title }
                panel.back()
                done()
              },
              // Esc closes it and opens nothing.
              function (done) {
                var n = panel.pages.length
                win.key(0, "g"); st.esc = { opened: picker.shown }
                win.key(Qt.Key_Escape, "")
                st.esc.closed = !picker.shown; st.esc.pages = panel.pages.length === n
                done()
              },
              // One artist: no picker, the page opens at once.
              function (done) {
                var n = panel.pages.length
                view.cursor = 1
                win.key(0, "g")
                st.one = { shown: picker.shown, pages: panel.pages.length - n, id: win.lastPage().id }
                panel.back()
                done()
              },
              // The button: the picker opens next to it; a click outside closes it.
              function (done) {
                view.cursor = 0
                // The buttons only exist while the pointer is on the row.
                var row0 = win.rowItem(list, 0)
                win.moveOnto(row0, row0.width - 20, row0.height / 2)
                var btn = win.artistButton(row0)
                list.actionAnchor = btn; list.action("artist", 0); list.actionAnchor = null
                var box = win.find(stage, "artistPickerBox")
                var bp = box.mapToItem(stage, 0, 0), ap = btn.mapToItem(stage, 0, 0)
                st.button = { shown: picker.shown, hasAnchor: picker.hasAnchor, inside: bp.x >= 0 && bp.x + box.width <= stage.width && bp.y >= 0 && bp.y + box.height <= stage.height,
                  nextToIt: Math.abs((bp.x + box.width) - (ap.x + btn.width)) < 2 }
                win.grab(outPicker, function () {
                  tc.mouseClick(picker, 3, 3)
                  st.button.closedByClick = !picker.shown
                  // A click on a name opens it.
                  list.actionAnchor = btn; list.action("artist", 0); list.actionAnchor = null
                  var n = panel.pages.length
                  tc.wait(150)
                tc.mouseClick(win.find(stage, "artistPick0"), 20, 10)
                  st.button.clickOpened = { shown: picker.shown, pages: panel.pages.length - n, id: win.lastPage().id }
                  panel.back()
                  done()
                })
              },
              // The artist text under a title is plain: no link in the rows, so no click and no underline.
              function (done) {
                var row0 = win.rowItem(list, 0)
                st.plain = { links: !!win.link(row0, 0), text: win.findAny(row0, function (c) { return typeof c.text === "string" && c.text.indexOf("berlioz") === 0 }) !== null }
                var n = panel.pages.length
                var t = win.findAny(row0, function (c) { return typeof c.text === "string" && c.text.indexOf("berlioz") === 0 })
                if (t) { var p = win.point(t, 5, t.height / 2); tc.mouseMove(stage, 2, 2); tc.wait(100); tc.mouseMove(stage, p.x, p.y); tc.wait(100); tc.mouseClick(stage, p.x, p.y); tc.wait(100) }
                // A long artist line is cut with "..." after a whole name part, never a bare comma.
                var row2 = win.rowItem(list, 2)
                var cut = !row2 ? null : win.findAny(row2, function (c) { return typeof c.text === "string" && c.text.indexOf("An artist") === 0 })
                st.plain.cut = cut ? cut.text : null
                st.plain.pages = panel.pages.length - n
                st.plain.pickerShown = picker.shown
                done()
              },
              // The now-playing line stays clickable: with several artists a click on a name opens the picker on it.
              function (done) {
                fakeSvc.player = Object.assign({}, fakeSvc.player, { artists: [{ name: "berlioz", id: "UCa1" }, { name: "Ted Jasper", id: "UCa2" }, { name: "Third Artist" }] })
                win.after(function () {
                  var l1 = win.findAny(win.find(stage, "nowArtistLine"), function (c) { return c.objectName === "artistLink2" })
                  tc.mouseClick(l1, 3, l1.height / 2)
                  st.now = { shown: picker.shown, names: picker.artists.map(function (a) { return a.name }), cursor: picker.cursor }
                  win.key(Qt.Key_Up, "")
                  var n = panel.pages.length
                  win.key(Qt.Key_Return, "")
                  st.now.opened = { shown: picker.shown, pages: panel.pages.length - n, id: win.lastPage().id }
                  panel.back()
                  console.log("STATE " + JSON.stringify(st))
                  Qt.quit()
                  done()
                })
              }
            ])
          })
        })
      }
    }
  }
}
