import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model

// What the account played lately, newest first, in the shelves YouTube
// Music groups it in (Today, Yesterday, ...). History exists only when
// signed in, Premium or not; signed out this is a quiet line, not a
// sign-in card and not a request.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property bool signedIn: svc ? svc.signedIn : false
  property var info: null
  property bool busy: false
  property string error: ""
  readonly property var rows: info ? Model.sectionRows(info.sections) : []
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: signedIn ? [["↵", "play"], ["e", "play next"]] : []

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false

  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }
  // Opening the tab reloads it: history changes as you listen, and a
  // failed load is retried the same way.
  function shown() { load() }

  function load() {
    if (!svc || !signedIn || busy) return
    view.busy = true
    view.error = ""
    svc.request("library", { section: "history" }, function (r) {
      view.busy = false
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.info = r.data
      list.cursor = Model.firstRow(view.rows)
    })
  }

  onSignedInChanged: { view.info = null; view.error = ""; if (signedIn && active) load() }

  RowList {
    id: list
    anchors.fill: parent
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: !view.signedIn ? "Sign in to YouTube Music to see your history"
      : view.busy && !view.info ? "Loading"
      : view.error !== "" ? view.error + ". Open this tab again to retry"
      : "Nothing played yet"
    onActivated: function (i) { view.panel.activateRow(view.rows[i], "") }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
  }
}
