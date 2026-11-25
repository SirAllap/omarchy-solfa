import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml on a short screen (test_short_screen.py): a song
// playing and a long playlist open, in a card no taller than the screen
// allows (SOLFA_CARD_MAX_H, as the shell's KeyboardPanel works it out), with
// the compactPanel setting from SOLFA_COMPACT_PANEL. Logs one "STATE {...}"
// line once the page has grown: the card, the song's part, the page's head,
// the list and the rows it shows whole (from the rows' own geometry); the
// card is saved to SOLFA_SCENE_OUT.
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
    // SOLFA_LATE_TRACK: the song starts only once the panel is open.
    property bool hasTrack: !Quickshell.env("SOLFA_LATE_TRACK")
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
    property string album: "Examples Live"
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
      startPaused: false, startVolume: "last", recycleHeapMb: 400, recycleHours: 12,
      compactPanel: Quickshell.env("SOLFA_COMPACT_PANEL") || undefined
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
      // A long playlist of the user's: one page of 40 songs.
      if (args.id === "VLPLlong" && !args.continuation) {
        var t = []
        for (var n = 1; n <= 40; n++) t.push(song("L" + ("0000000000" + n).slice(-10), "Song number " + n, "LSET" + n))
        return { kind: "playlist", title: "Long drive", subtitle: "40 songs", author: "Alex Example", thumb: "", playlistId: "PLlong", editable: true, tracks: t, continuation: "" }
      }
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

  // SOLFA_NO_WINDOW: the panel starts out of any window, as the shell's
  // does before its window is made, and only comes into this one later.
  readonly property bool noWindow: !!Quickshell.env("SOLFA_NO_WINDOW")
  Item { id: limbo }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 1500
    visible: true
    color: "transparent"

    Item {
      id: stage
      anchors.fill: parent
      SolfaPanel {
        id: panel
        svc: fakeSvc
        Component.onCompleted: if (scene.noWindow) panel.parent = limbo
      }
    }

    TestCase { id: tc; name: "short-screen"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    // Text items whose painted height does not fit their box (cut, not elided).
    function clipped(item, out) {
      out = out || []
      if (!item || !item.visible) return out
      if (item.hasOwnProperty("paintedHeight") && item.hasOwnProperty("text") && item.text !== "" && item.height > 0 && item.paintedHeight > item.height + 1)
        out.push(String(item.text).slice(0, 20))
      for (var i = 0; i < item.children.length; i++) clipped(item.children[i], out)
      return out
    }
    function box(name) {
      var it = win.find(stage, name)
      if (!it || !it.visible) return null
      var p = it.mapToItem(win.find(stage, "panelCard"), 0, 0)
      return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height) }
    }
    // The list's rows that show whole: each one's own box inside the list's.
    function wholeRows(list) {
      var n = 0
      for (var i = 0; i < list.count; i++) {
        var it = list.itemAtIndex(i)
        if (it && it.y >= list.contentY - 0.5 && it.y + it.height <= list.contentY + list.height + 0.5) n++
      }
      return n
    }

    Timer { id: settle; interval: 900; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    Timer {
      id: start
      interval: 300
      running: true
      onTriggered: {
        if (scene.noWindow) {
          // A while without a window (the panel measures what it can), then in.
          if (panel.parent === limbo) { win.after(function () { panel.parent = stage; win.after(function () { start.triggered() }) }); return }
        }
        panel.open()
        win.after(function () {
          fakeSvc.hasTrack = true
          panel.openPage({ browseId: "VLPLlong", title: "Long drive" })
          win.after(function () {
            var list = win.find(stage, "detailList")
            var row = list ? list.itemAtIndex(0) : null
            var st = {
              card: win.box("panelCard"), hero: win.box("panelHero"), tabs: win.box("panelTabs"), back: win.box("backRow"),
              head: win.box("detailHead"), list: win.box("detailList"), footer: win.box("footerHints"), play: win.box("playButton"),
              rowH: row ? row.height : 0, spacing: list ? list.spacing : 0, rows: list ? win.wholeRows(list) : 0,
              compact: panel.compact === true, compactHead: panel.compactHead === true,
              growth: panel.growth, maxCard: Number(Quickshell.env("SOLFA_CARD_MAX_H") || 0), fontScale: Style.fontScale,
              fullChrome: panel.fullChrome || 0, smallHeadSpan: win.find(stage, "detailView").smallHeadSpan || 0,
              compactSpan: win.find(stage, "detailView").compactSpan || 0,
              // Texts cut short in the song's part and the page's head (elided ones are fine: titles).
              clipped: win.clipped(win.find(stage, "panelHero")).concat(win.clipped(win.find(stage, "detailView")))
            }
            var out = Quickshell.env("SOLFA_SCENE_OUT")
            var done = function () { console.log("STATE " + JSON.stringify(st)); Qt.quit() }
            if (out) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(out); done() })
            else done()
          })
        })
      }
    }
  }
}
