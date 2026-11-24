import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml and its undo of a removal from a playlist
// (test_undo_remove.py): the notice "Removed from ..." offers Undo (and u)
// while it shows, for the last removal only, once; the song comes back where
// it was, as a new row, in the page and for Now Playing. Every step is read
// back from the live items and logged as one "STATE {...}" line; the panel
// with the notice is saved to SOLFA_SCENE_OUT when set. The service is fake:
// it records the requests and answers browse, playlist.remove and
// playlist.restore.
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
    function song(id, title, setId) { return { kind: "song", videoId: id, title: title, artists: [{ name: "The Examples" }], duration: 180, setVideoId: setId } }
    function tracks() { return [song("AAAAAAAAAAA", "One", "SET1"), song("BBBBBBBBBBB", "Two", "SET2"), song("CCCCCCCCCCC", "Three", "SET3"), song("DDDDDDDDDDD", "Four", "SET4"), song("EEEEEEEEEEE", "Five", "SET5")] }
    function page(args) {
      if (args.id === "VLPLmine" && !args.continuation)
        return { kind: "playlist", title: "Road trip", subtitle: "5 songs", author: "Alex Example", thumb: "", playlistId: "PLmine", editable: true, tracks: tracks(), continuation: "" }
      // A long one: three rows loaded, the next page after them.
      if (args.id === "VLPLlong" && !args.continuation)
        return { kind: "playlist", title: "Long drive", subtitle: "200 songs", author: "Alex Example", thumb: "", playlistId: "PLlong", editable: true,
                 tracks: [song("LLLLLLLLLL1", "L one", "LSET1"), song("LLLLLLLLLL2", "L two", "LSET2"), song("LLLLLLLLLL3", "L three", "LSET3")], continuation: "fixture-long-2" }
      if (args.id === "VLPLlong" && args.continuation === "fixture-long-2")
        return { kind: "playlist", title: "", tracks: [song("LLLLLLLLLL4", "L four", "LSET4"), song("LLLLLLLLLL5", "L five", "LSET5")], continuation: "fixture-long-3" }
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

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var st = {}
          var out = Quickshell.env("SOLFA_SCENE_OUT")
          panel.openPage({ browseId: "VLPLmine", title: "Road trip" })
          win.after(function () {
            var view = win.find(stage, "detailView")
            st.before = win.sets(view)
            // x on the second row: gone, and the notice offers Undo for a while.
            win.removeRow(view, "SET2")
            st.removed = { sets: win.sets(view), flash: panel.flash, offered: win.undoOffered(), ms: panel.undoMs }
            win.after(function () {
              st.removed.undo = win.undoShown()
              var shot = function (next) {
                if (out) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(out); next() })
                else next()
              }
              shot(function () {
                // u: the song comes back where it was, as a new row; once.
                st.u = { handled: win.key(0, "u") }
                st.u.sent = win.sent("playlist.restore")
                st.u.sets = win.sets(view)
                st.u.pageSets = view.page.info.tracks.map(function (t) { return t.setVideoId })
                st.u.flash = panel.flash
                st.u.undo = win.undoOffered()
                st.u.again = win.key(0, "u")
                st.u.asked = win.count("playlist.restore")
                // The last row, and a click on Undo: nothing to move before.
                win.removeRow(view, "SET5")
                win.clickUndo()
                st.last = { sent: win.sent("playlist.restore").pop(), sets: win.sets(view) }
                // Only the last removal: two rows out, Undo brings back the second.
                win.removeRow(view, "SET1")
                win.removeRow(view, "SET3")
                win.key(0, "u")
                st.onlyLast = { sent: win.sent("playlist.restore").pop(), sets: win.sets(view) }
                // The notice gone, or another one in its place: nothing to undo.
                var asked = win.count("playlist.restore")
                win.removeRow(view, "SET4")
                panel.flash = ""
                st.gone = { handled: win.key(0, "u") }
                win.removeRow(view, "NEW1")
                panel.say("Link copied")
                st.gone.replaced = win.key(0, "u")
                st.gone.asked = win.count("playlist.restore") - asked
                st.gone.sets = win.sets(view)
                // Put back, but not before the rows that followed it: at the end, and the panel says so.
                fakeSvc.placed = false
                win.removeRow(view, "NEW3")
                win.key(0, "u")
                st.unplaced = { flash: panel.flash, sets: win.sets(view) }
                fakeSvc.placed = true
                // An error: reported, nothing changes, and Undo is spent.
                fakeSvc.failOps = { "playlist.restore": "failed" }
                win.removeRow(view, "NEW4")
                var rows = win.sets(view)
                win.key(0, "u")
                st.failed = { reported: fakeSvc.reported.slice(-1), sets: win.sets(view), same: JSON.stringify(rows) === JSON.stringify(win.sets(view)), undo: win.undoOffered() }
                fakeSvc.failOps = ({})
                // Now Playing: a song whose row came back (SET5, now NEW2) plays; its queue entry
                // still names the old row, and the button holds for it. Taken out with the button,
                // it comes back again, and the button follows it to its newest row.
                st.np = { page: win.sets(view) }
                win.play("EEEEEEEEEEE", "PLmine", "SET5")
                win.after(function () {
                  st.np.renamed = panel.playingRemoval ? panel.playingRemoval.setVideoId : ""
                  win.find(stage, "removeButton").clicked()
                  st.np.removed = { sent: win.sent("playlist.remove").pop(), undo: win.undoOffered(), sets: win.sets(view), flash: panel.flash }
                  win.key(0, "u")
                  st.np.back = { sent: win.sent("playlist.restore").pop(), sets: win.sets(view),
                                 button: panel.playingRemoval ? panel.playingRemoval.setVideoId : "" }
                  // A long playlist: the last row loaded goes; its undo reads the next page for the rows after it.
                  panel.openPage({ browseId: "VLPLlong", title: "Long drive" })
                  win.after(function () {
                    var browses = win.count("browse")
                    win.removeRow(view, "LSET3")
                    win.key(0, "u")
                    var b = win.sent("browse")
                    st.long = { browse: b.slice(browses), sent: win.sent("playlist.restore").pop(), sets: win.sets(view) }
                    // With the find field open on a word: the found row goes and comes back, once.
                    // The next page is read first: a list that already fits its card (the grown
                    // detail card) never scrolls to its end, so nothing else would load it.
                    view.loadMore()
                    win.after(function () {
                    view.finding = true
                    view.query = "two"
                    st.finding = { before: win.sets(view) }
                    win.removeRow(view, "LSET2")
                    st.finding.removed = win.sets(view)
                    win.key(0, "u")
                    st.finding.back = win.sets(view)
                    st.finding.all = view.info.tracks.map(function (t) { return t.setVideoId })
                    console.log("STATE " + JSON.stringify(st))
                    Qt.quit()
                    })
                  })
                })
              })
            })
          })
        })
      }
    }
  }
}
