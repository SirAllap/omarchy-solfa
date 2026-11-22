import QtQuick
import "../lib/Calm.js" as Calm
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

  // Signed in, loaded, and empty: a calm card instead of one grey line.
  readonly property bool nothingYet: signedIn && !busy && error === "" && !!info && rows.length === 0
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: Calm.font

  onSignedInChanged: { view.info = null; view.error = ""; if (signedIn && active) load() }

  RowList {
    id: list
    anchors.fill: parent
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.nothingYet ? "" : !view.signedIn ? "Sign in to YouTube Music to see your history"
      : view.busy && !view.info ? "Loading"
      : view.error !== "" ? view.error + ". Open this tab again to retry"
      : "Nothing played yet"
    onActivated: function (i) { view.panel.activateRow(view.rows[i], "") }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
  }

  Column {
    objectName: "historyEmpty"
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    visible: view.nothingYet
    spacing: Style.space(6)
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Nothing played yet"
      textFormat: Text.PlainText
      color: view.fg
      font.family: view.family
      font.pixelSize: Style.font.title
      font.weight: Font.Bold
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: "Songs you play show up here, newest first."
      textFormat: Text.PlainText
      color: Util.alpha(view.fg, 0.64)
      font.family: view.family
      font.pixelSize: Style.font.body
    }
  }
}
