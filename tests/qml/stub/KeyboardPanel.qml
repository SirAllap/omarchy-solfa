import QtQuick
import qs.Commons

// Test stand-in for the Omarchy shell's KeyboardPanel (a layer-shell window
// that takes the keyboard). PanelScene.qml renders the real Panel.qml into
// this plain card instead: same content sizing and padding, same popups
// background and corner radius, but no window of its own, no keyboard grab
// and nothing mapped on the desktop.
Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  default property alias contentItem: contentHolder.children

  function fittedContentWidth(width, cap) {
    var w = Math.max(1, Number(width) || 1)
    return Math.round(cap !== undefined && Number(cap) > 0 ? Math.min(w, Number(cap)) : w)
  }
  function fittedContentHeight(implicitHeight, cap) {
    var h = (Number(implicitHeight) || 0) + root.padding * 2
    return Math.round(cap !== undefined && Number(cap) > 0 ? Math.min(h, Number(cap)) : h)
  }
  function cappedContentHeight(height) { return Math.round(Math.max(root.padding * 2, Number(height) || 0)) }

  width: root.contentWidth
  height: root.contentHeight
  visible: root.open

  Rectangle {
    id: card
    objectName: "panelCard"
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.margins: root.padding
    }
  }
}
