import QtQuick
import qs.Commons
import "../lib"

// A key and what it does. `keys` is the keys as typed in the hint tables:
// "n p" is two caps, "/" between them is plain muted text ("n / p"), so a
// cap is always exactly one key.
Row {
  id: hint

  property string keys: ""
  property string label: ""
  property QtObject bar: null
  // The label's size: the footer's by default; Settings passes a smaller one.
  property real labelPx: Style.space(11.5)
  // 0: as wide as it needs. Above 0 a long label is cut with an ellipsis, never the caps.
  property real maxWidth: 0
  property real keyPx: 0   // kept for callers that still pass it; the cap has one size
  readonly property string family: Calm.font
  // The keys without the Row's own gaps: " / " separators stay as text.
  readonly property var parts: String(keys).split(" ").filter(function (s) { return s !== "" })

  spacing: Style.space(6)

  Row {
    id: caps
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)
    Repeater {
      model: hint.parts
      delegate: Item {
        id: part
        required property string modelData
        readonly property bool sep: modelData === "/" || modelData === "or"
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: sep ? sepText.implicitWidth + Style.space(2) : cap.implicitWidth
        implicitHeight: cap.implicitHeight
        width: implicitWidth
        height: implicitHeight
        KeyCap { id: cap; visible: !part.sep; text: part.modelData }
        Text {
          id: sepText
          visible: part.sep
          anchors.centerIn: parent
          text: part.modelData
          textFormat: Text.PlainText
          color: Calm.muted
          font.family: hint.family
          font.pixelSize: hint.labelPx
        }
      }
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    width: hint.maxWidth > 0 ? Math.max(0, Math.min(implicitWidth, hint.maxWidth - caps.width - hint.spacing)) : implicitWidth
    elide: Text.ElideRight
    text: hint.label
    textFormat: Text.PlainText
    color: Calm.muted
    font.family: hint.family
    font.pixelSize: hint.labelPx
  }
}
