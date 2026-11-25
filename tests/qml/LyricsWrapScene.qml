import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

// The real Panel.qml on its Lyrics tab (test_lyrics_wrap.py): invented lyrics
// with lines longer than the panel is wide, synced (SOLFA_LYRICS=timed) or
// plain (SOLFA_LYRICS=plain). Logs one "STATE {...}" line per stop: the rows
// of the synced list, or the plain lines, as laid out (their own geometry,
// whether the text is cut short, how many lines it wraps to). SOLFA_SCENE_OUT
// is a prefix: the card is saved to <prefix>-<n>.png at each stop.
ShellRoot {
  id: scene

  readonly property bool plainMode: Quickshell.env("SOLFA_LYRICS") === "plain"
  // SOLFA_LYRICS=long: 120 mixed lines (short, empty, wrapping at 18 px, at
  // 22 px only, wrapping to 2 and 3 rows) and far jumps between them.
  readonly property bool longMode: Quickshell.env("SOLFA_LYRICS") === "long"
  readonly property var pool: [
    "Short line", "Lanterns drift along the harbour slowly", "",
    "A line of medium length that is long enough to need two rows",
    "Every window hums a tune that the whole street knows by heart and sings back to the sea",
    "Hush", "Tidal lights, tidal lights, carry the sleepless ones home across the water tonight and for good"
  ]
  // Words that wrap in several lines, a line that only wraps at the current
  // line's bigger size, and one word wider than the panel.
  readonly property var texts: [
    "\u266A", "Short line one", "Lanterns drift along the harbour",
    "Every window hums a tune that the whole street knows by heart and sings back to the sea",
    "Lanterns drift along the harbour slowly", "A line of medium length that is long enough to need two rows",
    "", "Another quiet line",
    "Supercalifragilisticexpialidocious_and_then_some_more_without_a_single_space_in_sight_for_the_wrapper",
    "Tidal lights, tidal lights, carry the sleepless ones home across the water tonight and for good",
    "The last short line", "Fin"
  ]

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
    // What the lyrics op answers (see lyricsFor below).
    property var lyricsData: ({ kind: "none" })
    property var reported: []
    function playing(id, list, setId) {
      return { videoId: id, title: "One", artists: [{ name: "The Examples" }], playing: true, volume: 70, duration: 180, position: 42,
               ad: false, playlistId: list, setVideoId: setId, index: 0, canNext: true }
    }
    function song(id, title, setId) { return { kind: "song", videoId: id, title: title, artists: [{ name: "The Examples" }], duration: 180, setVideoId: setId } }
    function request(op, args, cb) {
      log.push({ op: op, args: args })
      var reply = { ok: false, error: "not-found" }
      if (failOps[op]) reply = { ok: false, error: failOps[op] }
      else if (op === "lyrics") reply = { ok: true, data: lyricsData }
      else if (op === "queue") reply = { ok: true, data: { items: [], automix: [], index: 0, version: 1 } }
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

  Component.onCompleted: {
    var lines = []
    var src = longMode ? Array.from({ length: 120 }, function (_, n) { return pool[(n * 3 + Math.floor(n / 7)) % pool.length] }) : texts
    for (var i = 0; i < src.length; i++) lines.push({ t: i * 4000, text: src[i] })
    fakeSvc.lyricsData = plainMode ? { kind: "plain", text: texts.join("\n"), source: "Source: invented" }
                                   : { kind: "timed", lines: lines, source: "Source: invented" }
  }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 900
    visible: true
    color: "transparent"

    Item {
      id: stage
      anchors.fill: parent
      SolfaPanel { id: panel; svc: fakeSvc }
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function findAll(item, test, out) {
      out = out || []
      if (test(item)) out.push(item)
      for (var i = 0; i < item.children.length; i++) findAll(item.children[i], test, out)
      return out
    }

    Timer { id: settle; interval: 900; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    // The lyrics view's synced list (the ListView) and plain column (the
    // Flickable's content), found by what they are.
    function lyricsView() { return panel.view }
    function snapshot() {
      var v = lyricsView()
      var card = win.find(stage, "panelCard")
      var st = { width: v.width, height: v.height, fontScale: Style.fontScale, rows: [], texts: [] }
      if (scene.plainMode) {
        var col = win.findAll(v, function (c) { return c.hasOwnProperty("contentItem") && !c.hasOwnProperty("highlightRangeMode") && c.hasOwnProperty("contentHeight") })[0].contentItem.children[0]
        st.plainW = col.width
        for (var i = 0; i < col.children.length; i++) {
          var t = col.children[i]
          if (t.hasOwnProperty("lineCount")) st.texts.push({ i: i, truncated: t.truncated, lineCount: t.lineCount, h: t.height, painted: t.paintedHeight, text: String(t.text).slice(0, 12) })
        }
      } else {
        var list = win.findAll(v, function (c) { return c.hasOwnProperty("highlightRangeMode") })[0]
        st.listH = list.height
        st.contentY = list.contentY
        st.line = v.line
        for (var n = 0; n < list.count; n++) {
          var it = list.itemAtIndex(n)
          if (!it) continue
          // The row's own text and click area (a measuring Text may sit beside them).
          var tx = win.findAll(it, function (c) { return c.hasOwnProperty("lineCount") && c.visible })[0]
          var ma = win.findAll(it, function (c) { return c.hasOwnProperty("cursorShape") })[0]
          st.rows.push({ i: n, y: it.y - list.contentY, h: it.height, truncated: tx.truncated, lineCount: tx.lineCount, painted: tx.paintedHeight,
                         ty: it.y - list.contentY + tx.y, text: String(tx.text).slice(0, 12), mouseH: ma.height })
        }
      }
      return st
    }
    function stop(k, stops, out, done) {
      if (k >= stops.length) { done(); return }
      var s = stops[k]
      if (s.line !== undefined) fakeSvc.position = s.line * 4 + 0.5
      win.after(function () {
        var st = snapshot()
        st.stop = k
        console.log("STATE " + JSON.stringify(st))
        var prefix = Quickshell.env("SOLFA_SCENE_OUT")
        if (prefix) win.find(stage, "panelCard").grabToImage(function (r) { r.saveToFile(prefix + "-" + k + ".png"); win.stop(k + 1, stops, out, done) })
        else win.stop(k + 1, stops, out, done)
      })
    }

    Timer {
      running: true
      interval: 300
      onTriggered: {
        panel.open()
        win.after(function () {
          panel.showTab("lyrics")
          win.after(function () {
            var stops = scene.plainMode ? [{}] : scene.longMode ? [{ line: 3 }, { line: 100 }, { line: 5 }, { line: 119 }, { line: 0 }, { line: 60 }] : [{ line: 1 }, { line: 3 }, { line: 4 }, { line: 8 }, { line: 9 }, { line: 11 }, { line: 0 }, { line: 5 }]
            win.stop(0, stops, [], function () { Qt.quit() })
          })
        })
      }
    }
  }
}
