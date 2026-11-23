import QtQuick
import "../lib"
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// "Save to playlist": the playlists the song can go in (Recent, then All
// playlists, with their sizes), a field that filters them as you type, and
// "New playlist" at the top. A song a playlist has already is refused once
// ("Already in ..."); Enter again on that row adds it anyway. It covers the
// list under the tabs; the panel gives it the song (`item`) and takes the
// keys it does not use.
Rectangle {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  // The song being saved: { videoId, title }. Null while the picker is shut.
  property var item: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: Calm.font

  // null while the list is on its way.
  property var playlists: null
  property string error: ""
  property string query: ""
  property string newTitle: ""
  property bool creating: false
  property bool busy: false
  // The playlist that said it has the song: Enter on it again adds anyway.
  property string dupId: ""
  readonly property bool dupCurrent: !!(current && current.playlist && current.playlist.id === dupId)
  property int seq: 0
  property int cursor: 0

  readonly property var rows: Model.saveRows(playlists, query)
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property string emptyText: error !== "" ? error
    : playlists === null ? "Loading your playlists"
    : playlists.length === 0 ? "No playlists yet: press Enter to make the first one"
    : rows.length === 1 && query.trim() !== "" ? "No playlist matches" : ""

  color: Calm.surface
  radius: Style.spacing.labelGap
  clip: true

  onItemChanged: if (item) begin()

  function focusField() { field.forceActiveFocus() }

  function begin() {
    view.seq++
    view.playlists = null
    view.error = ""
    view.query = ""
    view.newTitle = ""
    view.creating = false
    view.busy = false
    view.dupId = ""
    view.cursor = 0
    field.text = ""
    field.forceActiveFocus()
    var s = view.seq
    view.svc.request("playlist.options", { videoId: view.item.videoId }, function (r) {
      if (s !== view.seq || !view.item) return
      if (r.ok) {
        view.playlists = r.data.playlists || []
        view.cursor = Model.firstPlaylistRow(view.rows)
      } else {
        view.error = Model.errorText(r.error)
      }
    })
  }

  function move(dy) { if (!view.creating) view.cursor = Model.moveCursor(view.rows, view.cursor, dy) }
  onCursorChanged: {
    var row = rows[cursor]
    if (!(row && row.playlist && row.playlist.id === dupId)) dupId = ""
  }

  function typed() {
    if (view.creating) { view.newTitle = field.text; return }
    view.query = field.text
    view.cursor = Model.firstPlaylistRow(view.rows)
  }

  // Esc: out of naming a playlist, else out of the picker.
  function back() {
    if (view.creating) {
      view.creating = false
      field.text = view.query
    } else {
      view.panel.closeSave()
    }
  }

  function accept() {
    if (view.busy || !view.item) return
    if (view.creating) { create(); return }
    var row = view.current
    if (!row || row.header) return
    if (row.create) {
      view.creating = true
      // What was typed to filter is a fine start for the name.
      view.newTitle = view.query.trim()
      field.text = view.newTitle
      field.selectAll()
    } else {
      save(row.playlist, row.playlist.id === view.dupId)
    }
  }

  function save(playlist, force) {
    view.busy = true
    var s = view.seq
    var args = { playlistId: playlist.id, videoId: view.item.videoId }
    if (force) args.force = true
    view.svc.request("playlist.add", args, function (r) {
      if (s !== view.seq || !view.item) return
      view.busy = false
      if (r.ok && r.data && r.data.duplicate) {
        view.dupId = playlist.id
        view.panel.say(Model.savedMessage(playlist.title, true))
      } else if (r.ok) {
        view.panel.say(Model.savedMessage(playlist.title, false))
        view.panel.closeSave()
      } else {
        view.panel.say(Model.errorText(r.error))
      }
    })
  }

  function create() {
    var title = view.newTitle.trim()
    if (title === "") { view.panel.say("Give the playlist a name"); return }
    if (title.length > 150) { view.panel.say("That name is too long"); return }
    view.busy = true
    var s = view.seq
    view.svc.request("playlist.create", { title: title, videoIds: [view.item.videoId] }, function (r) {
      if (s !== view.seq || !view.item) return
      view.busy = false
      if (r.ok) {
        view.panel.say("Saved to the new playlist " + title)
        view.panel.closeSave()
      } else {
        view.panel.say(Model.errorText(r.error))
      }
    })
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(8)

    Text {
      objectName: "saveTitle"
      width: parent.width
      text: view.item ? "Save “" + view.item.title + "” to a playlist" : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Util.alpha(view.fg, 0.7)
      font.family: view.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    TextField {
      id: field
      objectName: "saveField"
      width: parent.width
      placeholderText: view.creating ? "Name the new playlist" : "Type to filter your playlists"
      font.family: view.family
      maximumLength: 150
      onTextEdited: view.typed()
      onAccepted: view.accept()
      Keys.onEscapePressed: function (e) { view.back(); e.accepted = true }
      Keys.onUpPressed: function (e) { view.move(-1); e.accepted = true }
      Keys.onDownPressed: function (e) { view.move(1); e.accepted = true }
    }

    Item {
      width: parent.width
      height: parent.height - y

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        visible: view.creating || (view.emptyText !== "" && list.count <= 1)
        text: view.creating ? "Name it, then press Enter. It starts with this song." : view.emptyText
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Util.alpha(view.fg, 0.6)
        font.family: view.family
        font.pixelSize: Style.font.body
      }

      ListView {
        id: list
        objectName: "saveList"
        anchors.fill: parent
        visible: !view.creating
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: view.rows
        onCountChanged: if (view.cursor >= count) view.cursor = Math.max(0, count - 1)

        Connections {
          target: view
          function onCursorChanged() { if (view.cursor >= 0 && view.cursor < list.count) list.positionViewAtIndex(view.cursor, ListView.Contain) }
        }

        delegate: Item {
          id: cell
          required property var modelData
          required property int index
          readonly property bool selected: index === view.cursor
          readonly property var playlist: modelData.playlist || null
          readonly property bool isHeader: !!modelData.header
          width: ListView.view ? ListView.view.width : 0
          height: isHeader ? Style.space(28) : Style.space(40)

          // Rows arrive one after another, a short stagger; none under reduce-motion.
          opacity: 1
          Component.onCompleted: if (!Style.reduceMotion && view.item) arrive.start()
          SequentialAnimation {
            id: arrive
            PropertyAction { target: cell; property: "opacity"; value: 0 }
            PauseAnimation { duration: Math.min(cell.index, 10) * 22 }
            NumberAnimation { target: cell; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
          }

          Text {
            visible: cell.isHeader
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
            text: cell.modelData.header || ""
            textFormat: Text.PlainText
            color: Util.alpha(view.fg, 0.55)
            font.family: view.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Rectangle {
            visible: !cell.isHeader
            anchors.fill: parent
            radius: Style.spacing.labelGap
            color: cell.selected ? Style.selectedFillFor(view.fg, Color.accent)
              : rowHover.hovered ? Style.hoverFillFor(view.fg, Color.accent) : "transparent"
          }
          HoverHandler { id: rowHover; enabled: !cell.isHeader }
          MouseArea {
            visible: !cell.isHeader
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { view.cursor = cell.index; view.accept() }
          }

          Row {
            visible: !cell.isHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            // "New playlist" gets a plus.
            Text {
              id: mark
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              height: Style.space(22)
              text: cell.modelData.create ? Icons.plus : Icons.album
              opacity: cell.modelData.create ? 1 : 0.45
              textFormat: Text.PlainText
              color: cell.modelData.create ? Color.accent : view.fg
              font.family: view.family
              font.pixelSize: Style.font.icon
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - mark.width - kind.width - parent.spacing * 2
              text: cell.modelData.create ? "New playlist" : (cell.playlist ? cell.playlist.title : "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: view.fg
              font.family: view.family
              font.pixelSize: Style.font.body
              verticalAlignment: Text.AlignVCenter
              height: Style.space(22)
              font.bold: !!cell.modelData.create
            }
            Text {
              id: kind
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(96)
              horizontalAlignment: Text.AlignRight
              text: cell.playlist ? cell.playlist.count || "" : ""
              textFormat: Text.PlainText
              color: Util.alpha(view.fg, 0.45)
              font.family: view.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
