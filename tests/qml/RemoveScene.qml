import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml with "Remove from this playlist" (test_remove_from_playlist.py):
// x, Delete and the row's button take a song out of the user's own playlist;
// albums, other people's playlists and Liked songs have none of it; the
// queue still removes with x. Every step is read back from the live items
// and logged as one "STATE {...}" line; the panel is saved to SOLFA_SCENE_OUT
// when set. The service is fake: it records the requests and answers
// browse, playlist.remove, queue and queue.remove.
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
    property var log: []
    property var failOps: ({})
    // `hold`: playlist.remove is not answered until `held` is released.
    property bool hold: false
    property var held: []
    property var reported: []
    function song(id, title, setId) { return { kind: "song", videoId: id, title: title, artists: [{ name: "The Examples" }], duration: 180, setVideoId: setId } }
    // The same song twice (AAAAAAAAAAA), each with its own setVideoId.
    function tracks() { return [song("AAAAAAAAAAA", "One", "SET1"), song("BBBBBBBBBBB", "Two", "SET2"), song("AAAAAAAAAAA", "One", "SET3"), song("DDDDDDDDDDD", "Four", "SET4")] }
    function page(id) {
      if (id === "VLPLmine") return { kind: "playlist", title: "Road trip", subtitle: "4 songs", author: "Alex Example", thumb: "", playlistId: "PLmine", editable: true, tracks: tracks(), continuation: "" }
      if (id === "VLPLtheirs") return { kind: "playlist", title: "Shared mix", subtitle: "4 songs", author: "Someone", thumb: "", playlistId: "PLtheirs", editable: false, tracks: tracks(), continuation: "" }
      // A page that claims to be editable but is Liked songs: the view refuses on its own.
      if (id === "VLLM") return { kind: "playlist", title: "Liked songs", subtitle: "4 songs", author: "Alex Example", thumb: "", playlistId: "LM", editable: true, tracks: tracks(), continuation: "" }
      if (id === "MPREalbum") return { kind: "album", title: "An Album", subtitle: "2024", artists: [{ name: "The Examples" }], thumb: "", playlistId: "OLAKalbum", tracks: tracks() }
      return null
    }
    function request(op, args, cb) {
      calls.push(op)
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (op === "browse" && page(args.id)) reply = { ok: true, data: page(args.id) }
      else if (op === "queue") reply = { ok: true, data: { items: [song("AAAAAAAAAAA", "One", ""), song("BBBBBBBBBBB", "Two", ""), song("DDDDDDDDDDD", "Four", "")], automix: [], index: 0, version: 1 } }
      else if (op === "queue.remove") reply = { ok: true, data: {} }
      else if (failOps[op]) reply = { ok: false, error: failOps[op] }
      else if (op === "playlist.remove") {
        reply = { ok: true, data: { removed: true } }
        if (hold) { held.push(function () { cb(reply) }); return 0 }
      }
      if (cb) cb(reply)
      return 0
    }
    function report(code) { reported.push(code) }
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

    TestCase { id: tc; name: "remove-from-playlist"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    // Every item whose tooltip is `tip`, in the order the rows are laid out.
    function byTip(item, tip, out) {
      out = out || []
      if (item.tooltipText === tip) out.push(item)
      for (var i = 0; i < item.children.length; i++) byTip(item.children[i], tip, out)
      return out
    }
    function key(k, t) { panel.onKey({ key: k, text: t, modifiers: 0, accepted: false }) }
    function count(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).length }
    function sent(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).map(function (e) { return e.args }) }
    function titles(view) { return view.rows.map(function (r) { return r.item.title + "/" + r.item.setVideoId }) }

    Timer { id: settle; interval: 200; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    readonly property string removeTip: "Remove from this playlist (x)"

    // Opens a page from nothing and says what it shows.
    function openPage(id, title, cb) {
      panel.pages = []
      panel.openPage({ browseId: id, title: title })
      win.after(function () {
        var view = win.find(stage, "detailView")
        cb(view, { buttons: win.byTip(stage, win.removeTip).length, hints: view.hints.map(function (h) { return h[0] }), rows: view.rows.length })
      })
    }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var st = {}
          var out = Quickshell.env("SOLFA_SCENE_OUT")
          var next = function () {
            win.openPage("VLPLmine", "Road trip", function (view, mine) {
              st.mine = mine
              var buttons = win.byTip(stage, win.removeTip)
              st.mine.tip = buttons.length ? buttons[0].tooltipText : ""
              // x on the first row: one request with that row's ids, the row goes, the cursor stays.
              win.key(Qt.Key_X, "x")
              st.x = { sent: win.sent("playlist.remove"), rows: win.titles(view), cursor: view.cursor, flash: panel.flash,
                       pageRows: view.page.info.tracks.length, browses: win.count("browse"), subtitle: view.info.subtitle }
              panel.flash = ""
              // Delete on the second copy of a song that is in twice: its own setVideoId; the other copy of it was gone already.
              view.cursor = 1
              win.key(Qt.Key_Delete, "")
              st.del = { sent: win.sent("playlist.remove"), rows: win.titles(view), cursor: view.cursor, flash: panel.flash }
              panel.flash = ""
              // The row's button, on the last row: the cursor falls back to the new last row.
              view.cursor = 1
              win.after(function () {
                var btns = win.byTip(stage, win.removeTip)
                st.button = { count: btns.length }
                btns[1].clicked()
                st.button.sent = win.sent("playlist.remove")
                st.button.rows = win.titles(view)
                st.button.cursor = view.cursor
                st.button.flash = panel.flash
                panel.flash = ""
                // An error: the row stays, the service is told, no message of ours.
                fakeSvc.failOps = { "playlist.remove": "failed" }
                var before = win.count("playlist.remove")
                win.key(Qt.Key_X, "x")
                st.failed = { asked: win.count("playlist.remove") - before, rows: win.titles(view), reported: fakeSvc.reported.slice(), flash: panel.flash }
                // A second press while the first is on its way sends nothing more.
                fakeSvc.failOps = ({})
                fakeSvc.hold = true
                before = win.count("playlist.remove")
                win.key(Qt.Key_X, "x")
                win.key(Qt.Key_X, "x")
                win.key(Qt.Key_Delete, "")
                st.twice = { asked: win.count("playlist.remove") - before, rowsWhileWaiting: win.titles(view) }
                fakeSvc.hold = false
                fakeSvc.held.forEach(function (f) { f() })
                fakeSvc.held = []
                st.twice.rowsAfter = win.titles(view)
                st.twice.cursor = view.cursor
                st.twice.flash = panel.flash
                panel.flash = ""
                // A playlist of somebody else's, an album, Liked songs: no button, x and Delete send nothing.
                var quiet = function (id, title, name, cb) {
                  win.openPage(id, title, function (v, shown) {
                    var n = win.count("playlist.remove")
                    win.key(Qt.Key_X, "x")
                    win.key(Qt.Key_Delete, "")
                    st[name] = { buttons: shown.buttons, hints: shown.hints, rows: shown.rows, asked: win.count("playlist.remove") - n, left: v.rows.length, flash: panel.flash }
                    cb()
                  })
                }
                quiet("VLPLtheirs", "Shared mix", "theirs", function () {
                  quiet("MPREalbum", "An Album", "album", function () {
                    quiet("VLLM", "Liked songs", "liked", function () {
                      // The queue: x and Delete remove, as before.
                      var total = win.count("playlist.remove")
                      panel.pages = []
                      panel.showTab("queue")
                      win.after(function () {
                        var q = win.find(stage, "queueView")
                        q.cursor = 1
                        win.key(Qt.Key_X, "x")
                        win.key(Qt.Key_Delete, "")
                        st.queue = { sent: win.sent("queue.remove"), removeButtons: win.byTip(stage, "Remove (x)").length, playlistRemoves: win.count("playlist.remove") - total }
                        console.log("STATE " + JSON.stringify(st))
                        Qt.quit()
                      })
                    })
                  })
                })
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
