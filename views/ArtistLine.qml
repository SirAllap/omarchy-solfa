import QtQuick
import qs.Ui
import qs.Commons
import "../lib"

// A line of artist names where each name is its own link (hover underline,
// pointer, click). Same look as a plain Text line: the text before the names
// (a label, the explicit mark) and the commas stay plain and never take a click.
Item {
  id: root
  property var artists: []
  property string prefix: ""
  property color color: Calm.fg
  property string family: Calm.font
  property real pixelSize: Style.space(12)
  // True while the pointer is on the text: names never elide, and a line wider than
  // the room pans with the pointer, so every name can be reached and clicked.
  property bool scroll: false
  readonly property real contentWidth: line.childrenRect.width
  readonly property real overflow: Math.max(0, contentWidth - width)
  property real pan: 0
  onScrollChanged: if (!scroll) pan = 0

  // A name was clicked: { name, id } (id may be empty).
  signal artistClicked(var artist)

  readonly property var parts: {
    var out = []
    if (root.prefix) out.push({ text: root.prefix })
    var n = 0
    for (var i = 0; i < (root.artists || []).length; i++) {
      var a = root.artists[i]
      if (!a || !a.name) continue
      if (n++ > 0) out.push({ text: ", " })
      out.push({ text: a.name, artist: a })
    }
    return out
  }

  implicitHeight: line.implicitHeight
  height: implicitHeight

  // Where the pointer is on the line: the part under it stays under it as the line pans.
  HoverHandler {
    id: pointer
    enabled: root.scroll && root.overflow > 0
    onPointChanged: root.pan = root.overflow * Math.max(0, Math.min(1, point.position.x / Math.max(1, root.width)))
  }
  Item {
   anchors.fill: parent
   clip: true
   Row {
    id: line
    x: root.scroll && root.overflow > 0 ? -root.pan : 0
    Repeater {
      model: root.parts
      delegate: Text {
        id: part
        required property var modelData
        required property int index
        readonly property bool isLink: !!modelData.artist
        objectName: isLink ? "artistLink" + index : ""
        // Names that do not fit elide, like one Text would.
        width: root.scroll ? implicitWidth : Math.min(implicitWidth, Math.max(0, root.width - x))
        text: modelData.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.color
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.underline: isLink && linkArea.containsMouse
        MouseArea {
          id: linkArea
          objectName: "artistArea"
          enabled: part.isLink
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.artistClicked(part.modelData.artist)
        }
      }
    }
   }
  }
}
