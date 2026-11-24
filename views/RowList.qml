import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib"
import "../lib/Icons.js" as Icons
import "../lib/Motion.js" as Motion

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
  property bool isPlaying: true
  // The owner passes svc.panelOpen: the equalizers stand still in a closed panel.
  property bool panelOpen: true
  property var actionsFor: function (row) { return [] }
  property string emptyText: ""
  property color fg: Calm.fg
  property string family: Calm.font
  // A soft fade where more rows wait under the bottom edge, so none is cut hard.
  // DetailView draws its own (top and bottom) and turns this off.
  property bool fadeBottom: true

  // The panel's open clock (its content root's 'tms', 350 = settled).
  property real openMs: 350
  Component.onCompleted: {
    var p = list.parent
    while (p && !("tms" in p)) p = p.parent
    if (p) list.openMs = Qt.binding(function () { return p.tms })
  }

  signal activated(int index)
  signal action(string name, int index)
  // A name in a song row's artist line was clicked.
  signal artistActivated(int index, var artist)
  signal headerActivated(int index)

  model: rows
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  reuseItems: true
  cacheBuffer: 200
  spacing: Style.space(8)

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

  Rectangle {
    parent: list   // the viewport, not the scrolling content, and no layout parent to disturb
    z: 2
    visible: list.fadeBottom
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: Style.space(16)
    opacity: list.atYEnd ? 0 : 1
    Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(Calm.surface.r, Calm.surface.g, Calm.surface.b, 0) }
      GradientStop { position: 1; color: Calm.surface }
    }
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

    // The first 8 rows cascade up from 8 px below, 15 ms apart, from 110 ms.
    readonly property real rise: index < 8 ? Motion.effects(list.openMs, 110 + 15 * index, 130) : 1
    opacity: rise
    transform: Translate { y: Style.space(8) * (1 - cell.rise) }

    width: ListView.view ? ListView.view.width : 0
    // a soft press: the row gives to .98 and comes back, never in reduce-motion
    scale: !isHeader && hover.pressed && !Style.reduceMotion ? 0.98 : 1
    Behavior on scale { enabled: !Style.reduceMotion; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    height: isHeader ? Style.space(30) : Style.space(58)

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
        color: headerMouse.containsMouse ? Calm.accentText : Util.alpha(list.fg, 0.45)
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
      anchors.topMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      radius: Style.space(14)
      // The song that plays is tinted; the keyboard cursor is an outline; the
      // pointer is a faint wash (the calm mockup's three row states).
      color: cell.now ? Util.alpha(Calm.accent, 0.14)
        : rowHover.hovered || cell.selected ? Util.alpha(list.fg, 0.05) : "transparent"
      border.width: cell.selected ? 1 : 0
      border.color: Calm.a(Calm.accent, 0.8)
      Behavior on color { enabled: !Style.reduceMotion; ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

      // The playing row's bar grows from its middle, 220 ms.
      Rectangle {
        visible: height > 0
        x: 0; width: Style.space(3); radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        height: cell.now ? Style.space(24) : 0
        color: Calm.accent
        Behavior on height { enabled: !Style.reduceMotion && list.panelOpen; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }
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
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      RoundCover {
        width: Style.space(42)
        height: width
        cornerRadius: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        source: cell.item ? (cell.item.thumb || "") : ""
        foreground: list.fg
        fill: Util.alpha(list.fg, 0.08)
        fontFamily: list.family
        glyph: !cell.item ? Icons.note : cell.item.kind === "artist" ? Icons.artist : cell.item.kind === "album" ? Icons.album : Icons.note
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: rowContent.width - Style.space(42) - rowContent.spacing * 2 - trailing.width
        spacing: Style.space(2)
        // At rest the row's buttons are invisible: the text runs over their room, up to the
        // duration. The column keeps its narrow width, so the buttons never move.
        readonly property real restExtra: cell.showActions || cell.actions.length === 0 ? 0
          : trailing.width - (durationText.visible ? durationText.width + trailing.spacing : 0)

        Row {
          width: parent.width + parent.restExtra
          spacing: Style.space(6)
          Equalizer {
            visible: cell.now
            anchors.verticalCenter: parent.verticalCenter
            playing: list.isPlaying
            panelOpen: list.panelOpen
            reduceMotion: Style.reduceMotion
            color: Calm.accent
          }
          Text {
            width: parent.width - (cell.now ? 14 + parent.spacing : 0)
            text: cell.item ? cell.item.title : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: cell.now ? Calm.accent : list.fg
            font.family: list.family
            font.pixelSize: Style.space(14)
            font.weight: Font.DemiBold
          }
        }
        // A song's artists are links; every other row keeps its plain line.
        readonly property bool artistLinks: !!cell.item && !!cell.item.videoId && Model.artistsText(cell.item.artists) !== ""
        ArtistLine {
          width: parent.width + parent.restExtra
          visible: parent.artistLinks
          artists: cell.item ? cell.item.artists : []
          prefix: (cell.item && cell.item.explicit ? "E  " : "") + (cell.modelData.label ? cell.modelData.label + " · " : "")
          color: Util.alpha(list.fg, 0.6)
          family: list.family
          pixelSize: Style.space(12)
          onArtistClicked: function (a) { list.cursor = cell.index; list.artistActivated(cell.index, a) }
        }
        Text {
          width: parent.width + parent.restExtra
          text: parent.artistLinks ? "" : (cell.item && cell.item.explicit ? "E  " : "") + Model.labelled(cell.modelData.label, Model.rowSubtitle(cell.item))
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: text !== ""
          color: Util.alpha(list.fg, 0.6)
          font.family: list.family
          font.pixelSize: Style.space(12)
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
            // The common actions draw as thin vector icons, like the mockup.
            readonly property string vname: modelData.icon === Icons.savePlaylist ? "queue" : modelData.icon === Icons.close ? "close"
              : modelData.icon === Icons.plus ? "plus" : modelData.icon === Icons.play ? "play" : modelData.icon === Icons.artist ? "user" : ""
            iconText: vname === "" ? modelData.icon : ""
            iconSize: Style.space(20)
            VIcon { visible: actionButton.vname !== ""; anchors.centerIn: parent; name: actionButton.vname; size: Style.space(20); stroke: 1.7; filled: actionButton.vname === "play"; color: actionButton.foreground }
            foreground: actionButton.hot ? Calm.accent : Util.alpha(list.fg, 0.75)
            fontFamily: list.family
            tooltipText: modelData.tip
            onClicked: { list.cursor = cell.index; list.action(actionButton.modelData.name, cell.index) }
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }

        Text {
          id: durationText
          anchors.verticalCenter: parent.verticalCenter
          // No duration: no room kept for one, so the buttons end at the row's right margin.
          visible: !!(cell.item && cell.item.duration)
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
