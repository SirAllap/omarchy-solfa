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

  Row {
    id: line
    width: root.width
    clip: true
    Repeater {
      model: root.parts
      delegate: Text {
        id: part
        required property var modelData
        required property int index
        readonly property bool isLink: !!modelData.artist
        objectName: isLink ? "artistLink" + index : ""
        // Names that do not fit elide, like one Text would.
        width: Math.min(implicitWidth, Math.max(0, root.width - x))
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
