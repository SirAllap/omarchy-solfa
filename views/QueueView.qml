import QtQuick
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
    if (row.automix) return [{ name: "jump", icon: Icons.play, tip: "Play now" }, { name: "remove", icon: Icons.close, tip: "Remove (x)" }]
    var out = []
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

  RowList {
    id: list
    anchors.fill: parent
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: view.actionsFor
    emptyText: view.error !== "" ? view.error : "Nothing queued yet. Press / to find something."
    onActivated: function (i) { view.jump(view.rows[i]) }
    onAction: function (name, i) { view.runAction(name, view.rows[i]) }
  }
}
