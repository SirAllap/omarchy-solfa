import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml with Now Playing's "Remove from <playlist>" button
// (test_remove_playing.py): it is there only while the song playing comes
// from a playlist of the user's and the queue names its row; a press takes
// that row out of the playlist and nothing else. Every step is read back
// from the live items and logged as one "STATE {...}" line; the panel is
// saved to SOLFA_SCENE_OUT when set. The service is fake: it records the
// requests and answers browse, playlist.remove and queue.
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
    // Playing the second copy of a song that is in "Road trip" twice.
    property var player: playing("AAAAAAAAAAA", "PLmine", "SET3")
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
    function tracks() { return [song("AAAAAAAAAAA", "One", "SET1"), song("BBBBBBBBBBB", "Two", "SET2"), song("AAAAAAAAAAA", "One", "SET3"), song("DDDDDDDDDDD", "Four", "SET4")] }
    function page(id) {
      if (id === "VLPLmine") return { kind: "playlist", title: "Road trip", subtitle: "4 songs", author: "Alex Example", thumb: "", playlistId: "PLmine", editable: true, tracks: tracks(), continuation: "" }
      if (id === "VLPLtheirs") return { kind: "playlist", title: "Shared mix", subtitle: "4 songs", author: "Someone", thumb: "", playlistId: "PLtheirs", editable: false, tracks: tracks(), continuation: "" }
      // A browse whose page names another list than the one asked for.
      if (id === "VLPLodd") return { kind: "playlist", title: "Odd one", subtitle: "4 songs", author: "Alex Example", thumb: "", playlistId: "PLmine", editable: true, tracks: tracks(), continuation: "" }
      return null
    }
    function request(op, args, cb) {
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (op === "browse" && page(args.id)) reply = { ok: true, data: page(args.id) }
      else if (op === "queue") reply = { ok: true, data: { items: [song("AAAAAAAAAAA", "One", "SET3")], automix: [], index: 0, version: 1 } }
      else if (failOps[op]) reply = { ok: false, error: failOps[op] }
      else if (op === "playlist.remove" || op === "queue.removePlaying") {
        reply = { ok: true, data: { removed: true } }
        if (hold) { held.push(function () { cb(reply) }); return 0 }
      }
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

    TestCase { id: tc; name: "remove-playing"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function byTip(item, tip) {
      if (item.tooltipText === tip) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = byTip(item.children[i], tip)
        if (f) return f
      }
      return null
    }
    function count(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).length }
    function sent(op) { return fakeSvc.log.filter(function (e) { return e.op === op }).map(function (e) { return e.args }) }
    function browsed() { return win.sent("browse").map(function (a) { return a.id }) }
    function titles(view) { return view.rows.map(function (r) { return r.item.title + "/" + r.item.setVideoId }) }
    function button() { return win.find(stage, "removeButton") }
    // The button there with its playlist meaning ("Remove from <playlist>").
    function shown() { var b = win.button(); return !!(b && b.visible && b.meaning === "playlist") }
    function play(id, list, setId, extra) { fakeSvc.player = Object.assign(fakeSvc.playing(id, list, setId), extra || {}) }

    Timer { id: settle; interval: 200; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    // Where the button sits: in the transport row, after Save (and Share,
    // where there is one), its last button; the boxes of the row's buttons
    // left to right; the volume line under it.
    function layout() {
      var b = win.button(), save = win.find(stage, "saveButton")
      var mute = win.byTip(stage, "Mute (m)")
      var row = b.parent
      var visibleKids = []
      for (var i = 0; i < row.children.length; i++) if (row.children[i].visible) visibleKids.push(row.children[i])
      return {
        sameRow: save.parent === row,
        fromSave: visibleKids.slice(visibleKids.indexOf(save)).map(function (k) { return k.objectName }),
        rowWidth: Math.round(row.width),
        // What the redesign gives its seven buttons: 48 px squares, a 62 px play, 10 px gaps.
        sevenWidth: Math.round(Style.space(6 * 48 + 62 + 6 * 10)),
        x: Math.round(b.x),
        // In the row's own frame: the opening's scale and slide do not count.
        boxes: visibleKids.map(function (k) { return [Math.round(k.x), Math.round(k.width), Math.round(k.height)] }),
        sliderShown: mute.parent.children[1].visible,
        sliderWidth: Math.round(mute.parent.children[1].width),
        tip: b.tooltipText
      }
    }
    // The transport row's width, whatever it holds.
    function rowWidth() { return Math.round(win.find(stage, "saveButton").parent.width) }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var st = {}
          var out = Quickshell.env("SOLFA_SCENE_OUT")
          var next = function () {
            // Opened on a song playing from "Road trip": one browse of it, and the button.
            st.open = { shown: win.shown(), browsed: win.browsed(), layout: win.layout() }
            // More pushes about the same song ask nothing more.
            win.play("AAAAAAAAAAA", "PLmine", "SET3", { position: 50 })
            win.play("AAAAAAAAAAA", "PLmine", "SET3", { position: 51 })
            st.pushes = { browsed: win.browsed() }
            // The playlist's page open below, as the user left it.
            panel.openPage({ browseId: "VLPLmine", title: "Road trip" })
            win.after(function () {
              var view = win.find(stage, "detailView")
              st.pageBefore = win.titles(view)
              // Pressed twice while the request is out: one request, then the row goes.
              fakeSvc.hold = true
              win.button().clicked()
              win.button().clicked()
              st.twice = { sent: win.sent("playlist.remove"), shownWhileWaiting: win.shown() }
              fakeSvc.hold = false
              fakeSvc.held.forEach(function (f) { f() })
              fakeSvc.held = []
              st.removed = { shown: win.shown(), flash: panel.flash, page: win.titles(view), pageInfo: view.page.info.tracks.length,
                             browsed: win.browsed(), player: fakeSvc.player.videoId,
                             others: fakeSvc.log.filter(function (e) { return ["browse", "playlist.remove", "queue"].indexOf(e.op) < 0 }).map(function (e) { return e.op }) }
              panel.flash = ""
              // Another page on top; meanwhile the other copy of the song plays and is taken out too.
              panel.openPage({ browseId: "VLPLtheirs", title: "Shared mix" })
              win.after(function () {
                win.play("AAAAAAAAAAA", "PLmine", "SET1")
                win.after(function () {
                  st.otherCopy = { shown: win.shown(), browsed: win.browsed() }
                  win.button().clicked()
                  st.otherCopy.sent = win.sent("playlist.remove")[1]
                  st.otherCopy.flash = panel.flash
                  panel.flash = ""
                  // Back to "Road trip": the page kept in memory has lost both rows.
                  panel.back()
                  win.after(function () {
                    st.back = { page: win.titles(view), browsed: win.browsed() }
                    // An error: the button stays, the service is told, nothing else changes.
                    win.play("BBBBBBBBBBB", "PLmine", "SET2")
                    win.after(function () {
                      fakeSvc.failOps = { "playlist.remove": "failed" }
                      var before = win.count("playlist.remove")
                      win.button().clicked()
                      st.failed = { asked: win.count("playlist.remove") - before, shown: win.shown(), reported: fakeSvc.reported.slice(), flash: panel.flash, page: win.titles(view) }
                      fakeSvc.failOps = ({})
                      // None of these may show the button; only a new playlist is looked up.
                      var cases = [
                        ["noRow", ["AAAAAAAAAAA", "PLmine", ""]],
                        ["liked", ["AAAAAAAAAAA", "LM", "SET1"]],
                        ["radio", ["DDDDDDDDDDD", "RDAMPLPLmine", "SET4"]],
                        ["album", ["DDDDDDDDDDD", "OLAK5uy_album", "SET4"]],
                        ["theirs", ["DDDDDDDDDDD", "PLtheirs", "SET4"]],
                        ["otherList", ["DDDDDDDDDDD", "PLodd", "SET4"]],
                        ["otherSong", ["DDDDDDDDDDD", "PLmine", "SET2"]],
                        ["ad", ["DDDDDDDDDDD", "PLmine", "SET4", { ad: true }]],
                        ["signedOut", ["DDDDDDDDDDD", "PLmine", "SET4"]]
                      ]
                      st.hidden = {}
                      var step = function (i) {
                        if (i >= cases.length) return finish()
                        var c = cases[i]
                        if (c[0] === "ad") fakeSvc.isAd = true
                        if (c[0] === "signedOut") fakeSvc.signedIn = false
                        var b0 = win.browsed().length
                        win.play(c[1][0], c[1][1], c[1][2], c[1][3])
                        win.after(function () {
                          st.hidden[c[0]] = { shown: win.shown(), browsed: win.browsed().slice(b0), rowWidth: win.rowWidth() }
                          fakeSvc.isAd = false
                          step(i + 1)
                        })
                      }
                      var finish = function () {
                        // Signed in again: the playlist is looked up afresh (another account may own it).
                        fakeSvc.signedIn = true
                        win.after(function () {
                          st.signedInAgain = { shown: win.shown(), browsed: win.browsed().slice(-1) }
                          // The music video of the row's song plays instead (one queue entry
                          // pairs them): still that row, and the removal names the row's video.
                          win.play("EEEEEEEEEEE", "PLmine", "SET4", { entryVideoIds: ["DDDDDDDDDDD", "EEEEEEEEEEE"] })
                          st.twin = { shown: win.shown(), videoId: panel.playingRemoval ? panel.playingRemoval.videoId : "" }
                          // An entry whose videos are not the row's: no button.
                          win.play("EEEEEEEEEEE", "PLmine", "SET4", { entryVideoIds: ["XXXXXXXXXXX", "EEEEEEEEEEE"] })
                          st.twin.stranger = win.shown()
                          win.play("EEEEEEEEEEE", "PLmine", "SET4", { entryVideoIds: ["DDDDDDDDDDD", "EEEEEEEEEEE"] })
                          // x on the playing row in the page: Now Playing's button goes too.
                          var at = -1
                          for (var k = 0; k < view.rows.length; k++) if (view.rows[k].item.setVideoId === "SET4") at = k
                          view.cursor = at
                          panel.onKey({ key: Qt.Key_X, text: "x", modifiers: 0, accepted: false })
                          st.fromPage = { sent: win.sent("playlist.remove").pop(), shown: win.shown(), page: win.titles(view) }
                          // A song that is no row of a playlist of the user's: the same
                          // button, in the same place, takes it out of the queue.
                          win.play("CCCCCCCCCCC", "RDAMVMCCCCCCCCCCC", "", { index: 2, canNext: true })
                          var b = win.button()
                          st.queue = { meaning: b.meaning, visible: b.visible, enabled: b.enabled, tip: b.tooltipText,
                                       rowWidth: win.rowWidth(), x: Math.round(b.x), icon: b.children.filter(function (c) { return c.hasOwnProperty("stroke") }).map(function (c) { return c.name }) }
                          var removes = win.count("playlist.remove")
                          // The earlier Undo notice has run out (a lighter notice waits behind it).
                          panel.flash = ""; panel.undoable = null; panel.waitingNotice = null
                          fakeSvc.hold = true
                          b.clicked()
                          b.clicked()
                          st.queue.sent = win.sent("queue.removePlaying")
                          fakeSvc.hold = false
                          fakeSvc.held.forEach(function (f) { f() })
                          fakeSvc.held = []
                          st.queue.flash = panel.flash
                          st.queue.playlistRemoves = win.count("playlist.remove") - removes
                          panel.flash = ""
                          // Signed out, the queue still can.
                          fakeSvc.signedIn = false
                          st.queue.signedOut = win.button().meaning
                          fakeSvc.signedIn = true
                          // The first entry of the queue playing (index 0): the same request.
                          win.play("CCCCCCCCCCC", "RDAMVMCCCCCCCCCCC", "", { index: 0, canNext: true })
                          var before0 = win.count("queue.removePlaying")
                          st.queue.firstMeaning = b.meaning
                          b.clicked()
                          st.queue.first = win.sent("queue.removePlaying").slice(before0)
                          panel.flash = ""
                          // The last song, nothing after it: the button stays, and does nothing.
                          win.play("CCCCCCCCCCC", "RDAMVMCCCCCCCCCCC", "", { index: 2, canNext: false })
                          var asked = win.count("queue.removePlaying")
                          b.clicked()
                          st.queue.last = { meaning: b.meaning, visible: b.visible, enabled: b.enabled, tip: b.tooltipText, asked: win.count("queue.removePlaying") - asked }
                          // An error is reported, nothing else.
                          win.play("CCCCCCCCCCC", "RDAMVMCCCCCCCCCCC", "", { index: 2, canNext: true })
                          fakeSvc.failOps = { "queue.removePlaying": "moved" }
                          b.clicked()
                          st.queue.failed = { reported: fakeSvc.reported.slice(-1), flash: panel.flash }
                          fakeSvc.failOps = ({})
                          // During an advert it hides with Save and Share.
                          fakeSvc.isAd = true
                          st.queue.ad = win.button().visible
                          fakeSvc.isAd = false
                          console.log("STATE " + JSON.stringify(st))
                          Qt.quit()
                        })
                      }
                      step(0)
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
