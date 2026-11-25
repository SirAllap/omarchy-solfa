import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Icons.js" as Icons
import "../lib"

// Solfa's name, small and quiet, the gear (Settings) and the power button:
// power closes Solfa (the engine; the music stops) and, once closed, starts
// it again. Quiet like the name until the pointer comes; lit while closed
// or, for the gear, while Settings is open.
Row {
  id: root

  property var svc: null
  property color foreground: Calm.fg
  property string fontFamily: Calm.font
  property bool settingsOpen: false
  // The header is two instances: the name (left) and the buttons (right).
  property bool showLeft: true
  property bool showRight: true

  // Both instances build every child; only the one that shows a child names it,
  // so a lookup by objectName finds exactly one.
  signal gearClicked()

  readonly property bool closed: svc ? svc.closed === true : false
  readonly property bool reachable: svc ? svc.bridgeUp === true && !svc.signingIn : false

  // Account state, from the app's own page: a way in while signed out, a
  // badge for Premium. A free account, and a closed or starting engine
  // (nothing known yet), show neither.
  readonly property bool showSignIn: svc ? svc.ready && !svc.signedIn && !svc.signingIn : false
  readonly property bool showPremium: svc ? svc.ready && svc.premium : false

  // One muted tone for the mark, the name's pill text and the icons.
  readonly property color muted: Calm.accent

  // 14 px between the name's parts; the right-hand icons sit 36 px apart (their box).
  spacing: showLeft ? Style.space(14) : 0
  height: Style.space(36)

  Logo {
    visible: root.showLeft
    objectName: root.showLeft ? "brandLogo" : ""
    anchors.verticalCenter: parent.verticalCenter
    size: Style.space(36)
  }
  Text {
    visible: root.showLeft
    anchors.verticalCenter: parent.verticalCenter
    text: "Solfa"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.space(22)
    font.weight: Font.Bold
  }
  // Off with a last song: a small grey dot and "Off" after the name.
  Rectangle {
    id: offChip
    objectName: root.showLeft ? "offChip" : ""
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showLeft && root.closed && !!root.svc.lastTitle
    width: offRow.implicitWidth + Style.space(20)
    height: offRow.implicitHeight + Style.space(6)
    radius: height / 2
    color: Calm.wash
    Row {
      id: offRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Style.space(6); height: width; radius: width / 2; color: Calm.muted }
      Text {
        text: "Off"
        textFormat: Text.PlainText
        color: Calm.muted
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        font.weight: Font.Medium
      }
    }
  }
  Rectangle {
    id: premium
    objectName: root.showLeft ? "premiumBadge" : ""
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showLeft && root.showPremium
    width: premiumText.implicitWidth + Style.space(20)
    height: premiumText.implicitHeight + Style.space(4)
    radius: height / 2
    color: Calm.surface
    border.width: 1
    border.color: Calm.hair
    Text {
      id: premiumText
      anchors.centerIn: parent
      text: "Premium"
      textFormat: Text.PlainText
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
      font.weight: Font.Medium
    }
  }
  HitButton {
    id: signIn
    objectName: root.showRight ? "signInButton" : ""
    anchors.verticalCenter: parent.verticalCenter
    minSize: Style.space(28)
    text: "Sign in"
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    foreground: root.foreground
    bordered: true
    visible: root.showRight && root.showSignIn
    onClicked: if (root.svc) root.svc.signIn()
  }
  HitButton {
    id: gear
    objectName: root.showRight ? "gearButton" : ""
    anchors.verticalCenter: parent.verticalCenter
    minSize: Style.space(36)
    iconText: ""
    VIcon { anchors.centerIn: parent; name: "gear"; size: Style.space(22); stroke: 1.4; color: gear.foreground }
    foreground: root.muted
    selected: root.settingsOpen
    visible: root.showRight && root.reachable
    opacity: 1
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    tooltipText: "Settings"
    onClicked: root.gearClicked()
  }
  HitButton {
    id: power
    objectName: root.showRight ? "powerButton" : ""
    anchors.verticalCenter: parent.verticalCenter
    minSize: Style.space(36)
    iconText: ""
    VIcon { anchors.centerIn: parent; name: "power"; size: Style.space(22); stroke: 1.4; color: power.foreground }
    foreground: root.closed ? Calm.fg : root.muted
    selected: root.closed
    visible: root.showRight && root.reachable
    opacity: 1
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    tooltipText: root.closed ? "Turn Solfa on" : "Turn Solfa off — the music stops"
    onClicked: if (root.svc) root.svc.toggleEngine()
  }
}
