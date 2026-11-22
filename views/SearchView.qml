import QtQuick
import "../lib/Calm.js" as Calm
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// Search: a field, filter chips, and one list of results. With an empty
// field it shows YouTube Music's home shelves, so there is always
// something to play.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: Calm.font

  property string query: ""
  property string filter: ""
  property var result: null
  property var home: null
  property bool busy: false
  property string error: ""
  property int seq: 0

  readonly property bool inputFocused: field.activeFocus
  readonly property var rows: query.trim() === "" ? Model.sectionRows(home ? home.sections : [], 6) : Model.searchRows(result, filter)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: inputFocused
    ? [["↵", "search"], ["↓", "results"], ["esc", "clear"]]
    : [["↵", "play or open"], ["e", "play next"], ["a", "add to queue"], ["[ ]", "filter"]]

  readonly property var filters: [
    { key: "", label: "All" }, { key: "songs", label: "Songs" }, { key: "albums", label: "Albums" },
    { key: "artists", label: "Artists" }, { key: "playlists", label: "Playlists" }, { key: "videos", label: "Videos" }
  ]

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false
  function shown() { if (!home && svc && svc.ready) loadHome() }
  readonly property bool ready: svc ? svc.ready : false
  onReadyChanged: if (ready && active && !home) loadHome()
  function focusInput() { field.forceActiveFocus(); field.selectAll() }
  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  function loadHome() {
    if (!svc) return
    svc.request("home", {}, function (r) { if (r.ok) view.home = r.data })
  }

  function run() {
    var q = view.query.trim()
    if (!q) { view.result = null; view.error = ""; return }
    var s = ++view.seq
    view.busy = true
    view.error = ""
    var args = { q: q }
    if (view.filter) args.filter = view.filter
    svc.request("search", args, function (r) {
      if (s !== view.seq) return
      view.busy = false
      if (r.ok) {
        view.result = r.data
        list.cursor = Model.firstRow(view.rows)
      } else {
        view.error = Model.errorText(r.error)
      }
    })
  }

  function cycleFilter(d) {
    var i = 0
    for (var k = 0; k < filters.length; k++) if (filters[k].key === view.filter) i = k
    setFilter(filters[(i + d + filters.length) % filters.length].key)
  }

  function setFilter(key) {
    view.filter = key
    if (view.query.trim()) run()
  }

  // Enter in the field: search now and move to the results.
  function acceptField() {
    debounce.stop()
    run()
    panel.focusKeys()
  }

  function clearField() {
    if (field.text !== "") { field.text = ""; view.query = ""; view.result = null }
    else panel.focusKeys()
  }

  function headerActivated(index) {
    var more = rows[index] && rows[index].more
    if (more && view.query.trim()) setFilter(more)
    else if (more) panel.openPage({ browseId: more, title: rows[index].header }, rows[index].moreParams)
  }

  Timer { id: debounce; interval: 350; onTriggered: view.run() }

  Column {
    id: head
    width: parent.width
    spacing: Style.space(10)  // mockup: 10 px field-to-chips

    // The calm mockup's field: a 46 px pill, accent ring while it has focus.
    Rectangle {
      id: fieldBox
      width: parent.width
      height: Style.space(46)
      radius: height / 2
      color: field.activeFocus ? Calm.a(Calm.fg, 0.07) : Calm.wash
      border.width: field.activeFocus ? 1.5 : 1
      border.color: field.activeFocus ? Calm.a(Calm.accent, 0.85) : Calm.hair
      Behavior on color { enabled: !Style.reduceMotion; ColorAnimation { duration: 200 } }
      Behavior on border.color { enabled: !Style.reduceMotion; ColorAnimation { duration: 200 } }

      Text {
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.search
        color: field.activeFocus ? Calm.accent : Calm.a(Calm.fg, 0.64)
        font.pixelSize: Style.space(19)
      }
      Text {
        x: Style.space(46)
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text === ""
        text: "Search songs, albums, artists and playlists"
        color: Calm.a(Calm.fg, 0.36)
        font.family: view.family
        font.pixelSize: Style.space(14)
      }
      TextInput {
        id: field
        anchors.left: parent.left
        anchors.leftMargin: Style.space(46)
        anchors.right: clearButton.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: Calm.fg
        selectionColor: Calm.a(Calm.accent, 0.5)
        selectedTextColor: Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(15)
        onTextEdited: { view.query = text; debounce.restart() }
        onAccepted: view.acceptField()
        Keys.onEscapePressed: function (e) { view.clearField(); e.accepted = true }
        Keys.onDownPressed: function (e) { view.panel.focusKeys(); if (view.cursor < 0) view.move(1); e.accepted = true }
      }
      Item {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: field.text !== "" ? Style.space(30) : 0
        height: Style.space(30)
        visible: field.text !== ""
        Text {
          anchors.centerIn: parent
          text: Icons.close
          color: clearMouse.containsMouse ? Calm.fg : Calm.a(Calm.fg, 0.64)
          font.pixelSize: Style.space(14)
        }
        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { field.text = ""; view.query = ""; view.result = null; field.forceActiveFocus() }
        }
      }
    }

    Row {
      spacing: Style.space(6)
      visible: view.query.trim() !== ""
      Repeater {
        model: view.filters
        delegate: PillChip {
          required property var modelData
          text: modelData.label
          family: view.family
          on: view.filter === modelData.key
          onClicked: view.setFilter(modelData.key)
        }
      }
    }
  }

  RowList {
    id: list
    anchors.top: head.bottom
    anchors.topMargin: Style.space(12)  // mockup: list 12 px under the chips
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    panelOpen: !!(view.svc && view.svc.panelOpen)
    isPlaying: view.svc ? view.svc.isPlaying !== false : true
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Searching" : view.error !== "" ? view.error
      : view.query.trim() !== "" ? "No results" : (view.home ? "" : "Loading suggestions")
    onActivated: function (i) { view.panel.activateRow(view.rows[i]) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { view.headerActivated(i) }
  }
}
