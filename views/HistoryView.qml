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
  // Shelf titles read as small-caps labels (TODAY, YESTERDAY), as in the mockup.
  readonly property var rows: info ? Model.sectionRows(info.sections).map(function (r) {
    return r.header ? { header: String(r.header).toUpperCase(), more: r.more, moreParams: r.moreParams } : r
  }) : []
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
  readonly property bool loading: signedIn && busy && !info
  readonly property color fg: bar ? bar.foreground : Calm.fg
  readonly property string family: Calm.font

  onSignedInChanged: { view.info = null; view.error = ""; if (signedIn && active) load() }

  RowList {
    id: list
    anchors.fill: parent
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.nothingYet || view.loading ? "" : !view.signedIn ? "Sign in to YouTube Music to see your history"
      : view.error !== "" ? view.error + ". Open this tab again to retry"
      : "Nothing played yet"
    onActivated: function (i) { view.panel.activateRow(view.rows[i], "") }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
  }

  // Loading: four faint rows, breathing slowly (as in the queue).
  Column {
    objectName: "historyLoading"
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
      model: [0.55, 0.7, 0.85, 0.6]
      delegate: Row {
        id: sk
        required property real modelData
        spacing: 12
        Rectangle { width: 40; height: width; radius: 10; color: Util.alpha(view.fg, 0.08) }
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
    objectName: "historyEmpty"
    anchors.centerIn: parent
    width: parent.width - 40
    visible: view.nothingYet
    spacing: 6
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Nothing played yet"
      textFormat: Text.PlainText
      color: view.fg
      font.family: view.family
      font.pixelSize: 16
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
      font.pixelSize: 13
    }
  }
}
