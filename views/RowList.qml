import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// One list for every view: section headers and rows, a keyboard cursor, and
// per-row actions that show on hover or on the cursor row.
//
//   rows: [{ header, more } | { item, current, automix, queueIndex }]
//   actionsFor(row) → [{ name, icon, tip }]
ListView {
  id: list

  property var rows: []
  property int cursor: -1
  property QtObject bar: null
  property string playingId: ""
  property var actionsFor: function (row) { return [] }
  property string emptyText: ""
  property color fg: bar ? bar.foreground : Color.foreground
  property string family: bar ? bar.fontFamily : Style.font.family

  signal activated(int index)
  signal action(string name, int index)
  signal headerActivated(int index)

  model: rows
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  reuseItems: true
  cacheBuffer: 200
  spacing: 0

  onCursorChanged: if (cursor >= 0 && cursor < count) positionViewAtIndex(cursor, ListView.Contain)
  onRowsChanged: if (cursor >= rows.length) cursor = Model.firstRow(rows)

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    visible: list.rows.length === 0 && list.emptyText !== ""
    text: list.emptyText
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(list.fg, 0.6)
    font.family: list.family
    font.pixelSize: Style.font.body
  }

  delegate: Item {
    id: cell
    required property var modelData
    required property int index
    readonly property bool isHeader: !!modelData.header
    readonly property var item: modelData.item || null
    readonly property bool selected: index === list.cursor
    readonly property bool now: !!item && !!item.videoId && (modelData.current === true || (modelData.current === undefined && !modelData.automix && item.videoId === list.playingId))
    readonly property var actions: isHeader ? [] : list.actionsFor(modelData)
    // A handler, not the MouseArea: it stays hovered while the pointer is on
    // one of the row's own buttons, so they do not hide under it.
    readonly property bool showActions: selected || rowHover.hovered

    width: ListView.view ? ListView.view.width : 0
    height: isHeader ? Style.space(30) : Style.space(46)

    // ---- section header
    Row {
      visible: cell.isHeader
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(5)
      spacing: Style.space(8)

      Text {
        text: cell.modelData.header || ""
        textFormat: Text.PlainText
        color: Util.alpha(list.fg, 0.55)
        font.family: list.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        visible: !!cell.modelData.more
        text: "Show all"
        textFormat: Text.PlainText
        color: headerMouse.containsMouse ? Color.accent : Util.alpha(list.fg, 0.45)
        font.family: list.family
        font.pixelSize: Style.font.caption
        font.underline: headerMouse.containsMouse
        MouseArea {
          id: headerMouse
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: list.headerActivated(cell.index)
        }
      }
    }

    // ---- row
    Rectangle {
      visible: !cell.isHeader
      anchors.fill: parent
      radius: Style.spacing.labelGap
      color: cell.selected ? Style.selectedFillFor(list.fg, Color.accent)
        : rowHover.hovered ? Style.hoverFillFor(list.fg, Color.accent) : "transparent"
    }

    HoverHandler { id: rowHover; enabled: !cell.isHeader }

    MouseArea {
      id: hover
      visible: !cell.isHeader
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { list.cursor = cell.index; list.activated(cell.index) }
    }

    Row {
      id: rowContent
      visible: !cell.isHeader
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      RoundCover {
        width: Style.space(32)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        source: cell.item ? (cell.item.thumb || "") : ""
        foreground: list.fg
        fill: Util.alpha(list.fg, 0.08)
        fontFamily: list.family
        glyph: !cell.item ? Icons.note : cell.item.kind === "artist" ? Icons.artist : cell.item.kind === "album" ? Icons.album : Icons.note
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: rowContent.width - Style.space(32) - rowContent.spacing * 2 - trailing.width
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: (cell.now ? Icons.play + " " : "") + (cell.item ? cell.item.title : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: cell.now ? Color.accent : list.fg
          font.family: list.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          text: (cell.item && cell.item.explicit ? "E  " : "") + Model.rowSubtitle(cell.item)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: text !== ""
          color: Util.alpha(list.fg, 0.6)
          font.family: list.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: trailing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        // Always laid out, shown on hover or on the cursor row: the title
        // keeps its width, so nothing jumps when the pointer arrives.
        Repeater {
          model: cell.actions
          delegate: HitButton {
            id: actionButton
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            opacity: cell.showActions ? 1 : 0
            enabled: cell.showActions
            iconText: modelData.icon
            iconSize: Style.font.icon
            foreground: actionButton.hot ? Color.accent : Util.alpha(list.fg, 0.75)
            fontFamily: list.family
            tooltipText: modelData.tip
            onClicked: { list.cursor = cell.index; list.action(actionButton.modelData.name, cell.index) }
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          horizontalAlignment: Text.AlignRight
          text: cell.item && cell.item.duration ? Model.fmtTime(cell.item.duration) : ""
          textFormat: Text.PlainText
          color: Util.alpha(list.fg, 0.5)
          font.family: list.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
