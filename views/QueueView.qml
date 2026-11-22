import QtQuick
import "../lib/Calm.js" as Calm
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// The queue: what plays next, and what autoplay would add after it.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null

  // On screen: the panel is open on this view. (`visible` stays true in a
  // closed panel's hidden window.)
  property bool active: false
  property var queue: null
  property string error: ""
  // The song J/K just moved: the cursor follows it once the queue reloads.
  property string follow: ""
  readonly property var rows: Model.queueRows(queue)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: [["↵", "play"], ["x", "remove"], ["J K", "move"]]

  function shown() { load(true) }
  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  function load(jumpToCurrent) {
    if (!svc) return
    svc.request("queue", {}, function (r) {
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.error = ""
      var keep = view.follow || (view.current && view.current.item ? view.current.item.videoId : "")
      view.follow = ""
      view.queue = r.data
      if (jumpToCurrent || !keep) {
        list.cursor = r.data.index >= 0 ? r.data.index : Model.firstRow(view.rows)
      } else {
        for (var i = 0; i < view.rows.length; i++) if (view.rows[i].item && view.rows[i].item.videoId === keep && !view.rows[i].automix) { list.cursor = i; return }
      }
    })
  }

  function actionsFor(row) {
    if (!row || !row.item) return []
    var save = { name: "save", icon: Icons.savePlaylist, tip: "Save to a playlist (S)" }
    if (row.automix) return [{ name: "jump", icon: Icons.play, tip: "Play now" }, save, { name: "remove", icon: Icons.close, tip: "Remove (x)" }]
    var out = [save]
    if (row.queueIndex > 0) out.push({ name: "up", icon: Icons.up, tip: "Move up (K)" })
    if (view.queue && row.queueIndex < view.queue.items.length - 1) out.push({ name: "down", icon: Icons.down, tip: "Move down (J)" })
    if (!row.current) out.push({ name: "remove", icon: Icons.close, tip: "Remove (x)" })
    return out
  }

  function done(r) { if (!r.ok) view.error = Model.errorText(r.error) }

  function jump(row) { if (row && row.item) svc.request("queue.jump", { index: row.queueIndex, automix: !!row.automix }, done) }
  function remove(row) {
    if (!row || !row.item) return
    if (row.current) { view.error = Model.errorText("playing"); return }
    svc.request("queue.remove", { index: row.queueIndex, automix: !!row.automix }, done)
  }
  function shift(row, d) {
    if (!row || !row.item || row.automix || !view.queue) return
    var to = row.queueIndex + d
    if (to < 0 || to >= view.queue.items.length) return
    // The reload after the move puts the cursor back on this song.
    view.follow = row.item.videoId
    svc.request("queue.move", { from: row.queueIndex, to: to }, function (r) { done(r) })
  }

  function runAction(name, row) {
    if (name === "jump") jump(row)
    else if (name === "save") panel.saveRow(row)
    else if (name === "remove") remove(row)
    else if (name === "up") shift(row, -1)
    else if (name === "down") shift(row, 1)
  }

  // Keys only the queue has.
  function key(t) {
    if (t === "x") { remove(view.current); return true }
    if (t === "K") { shift(view.current, -1); return true }
    if (t === "J") { shift(view.current, 1); return true }
    return false
  }
  function activate() { jump(view.current) }

  Timer { id: reload; interval: 120; onTriggered: view.load(false) }

  Connections {
    target: view.svc
    function onQueueChanged() { if (view.active) reload.restart() }
  }

  // "UP NEXT  8 songs · 29 min": what is still to play (from the song now).
  readonly property var upNext: {
    var items = queue && queue.items ? queue.items : []
    var from = queue && queue.index >= 0 ? queue.index : 0
    var n = 0, secs = 0
    for (var i = from; i < items.length; i++) { n++; secs += Number(items[i].duration) || 0 }
    return { n: n, min: Math.round(secs / 60) }
  }
  Item {
    id: qHead
    visible: view.upNext.n > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: visible ? 28 : 0
    Row {
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "UP NEXT"
        textFormat: Text.PlainText
        color: Util.alpha(Calm.fg, 0.55)
        font.family: Calm.font
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.2
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: view.upNext.n + (view.upNext.n === 1 ? " song" : " songs") + (view.upNext.min > 0 ? " · " + view.upNext.min + " min" : "")
        textFormat: Text.PlainText
        color: Util.alpha(Calm.fg, 0.5)
        font.family: Calm.font
        font.pixelSize: 11
      }
    }
  }

  RowList {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: qHead.bottom
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    panelOpen: !!(view.svc && view.svc.panelOpen)
    isPlaying: view.svc ? view.svc.isPlaying !== false : true
    actionsFor: view.actionsFor
    // The empty, loading and error states are drawn by `state` below.
    emptyText: ""
    onActivated: function (i) { view.jump(view.rows[i]) }
    onAction: function (name, i) { view.runAction(name, view.rows[i]) }
  }

  // ---- empty / loading / error: one calm centred state, no list behind it.
  readonly property color fg: bar ? bar.foreground : Calm.fg
  // The calm error tone of the mockup (Theme.err).
  readonly property color err: Qt.rgba(0.725, 0.439, 0.486, 1)
  readonly property string family: Calm.font
  readonly property bool loading: !!svc && queue === null && error === ""
  readonly property bool failed: rows.length === 0 && error !== ""
  readonly property bool empty: rows.length === 0 && !loading && !failed

  // Loading: five faint rows, breathing slowly.
  Column {
    objectName: "queueLoading"
    visible: view.loading
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 8
    spacing: 10
    opacity: 0.6
    SequentialAnimation on opacity {
      running: view.loading && view.visible && view.active && !Style.reduceMotion
      loops: Animation.Infinite
      NumberAnimation { from: 0.45; to: 0.9; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.9; to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
    }
    Repeater {
      model: [0.55, 0.7, 0.85, 0.6, 0.75]
      delegate: Row {
        id: sk
        required property real modelData
        spacing: 12
        Rectangle { width: 40; height: width; radius: 8; color: Util.alpha(view.fg, 0.08) }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Rectangle { width: (view.width - 80) * sk.modelData; height: 9; radius: height / 2; color: Util.alpha(view.fg, 0.1) }
          Rectangle { width: (view.width - 80) * sk.modelData * 0.6; height: 7; radius: height / 2; color: Util.alpha(view.fg, 0.06) }
        }
      }
    }
  }

  Column {
    objectName: "queueState"
    visible: view.empty || view.failed
    anchors.centerIn: parent
    width: parent.width - 40
    spacing: 10

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 56
      height: width
      radius: 16
      color: view.failed ? Util.alpha(view.err, 0.14) : Util.alpha(view.fg, 0.06)
      border.width: 1
      border.color: view.failed ? Util.alpha(view.err, 0.5) : Util.alpha(view.fg, 0.14)
      Text {
        anchors.centerIn: parent
        text: view.failed ? "!" : Icons.playNext
        textFormat: Text.PlainText
        color: view.failed ? view.err : Calm.accent
        font.family: view.family
        font.pixelSize: 28
        font.bold: view.failed
      }
    }
    Text {
      width: parent.width
      text: view.failed ? "Could not load the queue" : "The queue is empty"
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: view.fg
      font.family: view.family
      font.pixelSize: 16
      font.bold: true
    }
    Text {
      width: parent.width
      text: view.failed ? view.error : "Add songs from Search or Library, or start a radio from any song."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      color: Util.alpha(view.fg, 0.6)
      font.family: view.family
      font.pixelSize: 13
    }
    HitButton {
      objectName: view.failed ? "queueRetry" : "queueSearch"
      anchors.horizontalCenter: parent.horizontalCenter
      text: view.failed ? "Try again" : "Search for music"
      iconText: view.failed ? Icons.repeat : Icons.search
      fontFamily: view.family
      foreground: view.failed ? view.fg : Calm.bg
      background: view.failed ? Util.alpha(view.fg, 0.08) : Calm.accent
      radius: height / 2
      onClicked: if (view.failed) view.load(true); else if (view.panel) view.panel.showTab("search")
    }
  }
}
