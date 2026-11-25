import QtQuick
import Quickshell
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
  // Like the shell's KeyboardPanel: a plugin may replace the border (settable),
  // the radius and the background are fixed there (KeyboardPanel.qml:514, :517).
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  default property alias contentItem: contentHolder.children

  function fittedContentWidth(width, cap) {
    var w = Math.max(1, Number(width) || 1)
    return Math.round(cap !== undefined && Number(cap) > 0 ? Math.min(w, Number(cap)) : w)
  }
  // The screen's room for the card, as the shell's KeyboardPanel works it
  // out (screen height less bar, gap and margin): SOLFA_CARD_MAX_H, else 0
  // (no screen known, no limit).
  readonly property real availableCardHeight: Number(Quickshell.env("SOLFA_CARD_MAX_H") || 0)
  function fittedContentHeight(implicitHeight, cap) {
    var h = (Number(implicitHeight) || 0) + root.padding * 2
    var most = root.availableCardHeight > 0 ? root.availableCardHeight : h
    if (cap !== undefined && Number(cap) > 0) most = Math.min(most, Number(cap))
    return Math.round(Math.min(h, most))
  }
  function cappedContentHeight(height) {
    var h = Math.max(root.padding * 2, Number(height) || 0)
    return Math.round(root.availableCardHeight > 0 ? Math.min(h, root.availableCardHeight) : h)
  }

  width: root.contentWidth
  height: root.contentHeight
  visible: root.open

  Rectangle {
    id: card
    objectName: "panelCard"
    anchors.fill: parent
    property var borderSpec: root.borderSpec
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Border.top(borderSpec)
    border.color: Border.color(borderSpec)

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.margins: root.padding
    }
  }
}
