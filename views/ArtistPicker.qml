import QtQuick
import "../lib"
import qs.Ui
import qs.Commons

// "Go to artist" on a song with several artists: a small menu next to the button
// (or in the middle when the key opened it) that lists every artist by name. The
// panel gives it the artists and a place (`anchor`: a rect in this item's coordinates)
// and takes the keys: Up/Down move, Enter opens, Esc closes (move/act/dismissed).
// A click on a name opens it; a click anywhere else closes. Same look as the
// Settings dropdown menu.
Item {
  id: root
  property var artists: []
  property rect anchor: Qt.rect(0, 0, 0, 0)
  property bool hasAnchor: false
  property string family: Calm.font
  property int cursor: 0
  readonly property bool shown: artists.length > 1

  signal picked(var artist)
  signal dismissed()

  visible: shown
  z: 60
  onArtistsChanged: cursor = 0

  function move(d) { if (artists.length) cursor = (cursor + d + artists.length) % artists.length }
  function act() { if (cursor >= 0 && cursor < artists.length) root.picked(artists[cursor]) }

  MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

  Rectangle {
    id: box
    objectName: "artistPickerBox"
    width: Math.min(root.width - Style.space(16), Style.space(220))
    height: col.implicitHeight + Style.space(12)
    // Under the button, right edges level; above it when there is no room below;
    // from the key: the middle of the card.
    x: root.hasAnchor ? Math.max(Style.space(8), Math.min(root.width - width - Style.space(8), root.anchor.x + root.anchor.width - width))
      : (root.width - width) / 2
    y: root.hasAnchor
      ? (root.anchor.y + root.anchor.height + Style.space(6) + height <= root.height ? root.anchor.y + root.anchor.height + Style.space(6)
        : Math.max(0, root.anchor.y - height - Style.space(6)))
      : (root.height - height) / 3
    radius: Style.space(14)
    color: Calm.raised
    border.width: 1
    border.color: Calm.hair
    Column {
      id: col
      anchors.fill: parent
      anchors.margins: Style.space(6)
      Repeater {
        model: root.artists
        delegate: Rectangle {
          required property var modelData
          required property int index
          objectName: "artistPick" + index
          readonly property bool hot: index === root.cursor
          width: col.width
          height: Style.space(34)
          radius: Style.space(10)
          color: hot ? Calm.a(Calm.accent, 0.22) : "transparent"
          Text {
            anchors.left: parent.left; anchors.leftMargin: Style.space(12)
            anchors.right: parent.right; anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: parent.hot ? Calm.accentText : Calm.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.cursor = index
            onClicked: root.picked(modelData)
          }
        }
      }
    }
  }
}
