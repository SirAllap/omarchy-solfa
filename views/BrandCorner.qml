import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Icons.js" as Icons
import "../lib/Calm.js" as Calm

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

  signal gearClicked()

  readonly property bool closed: svc ? svc.closed === true : false
  readonly property bool reachable: svc ? svc.bridgeUp === true && !svc.signingIn : false

  // Account state, from the app's own page: a way in while signed out, a
  // badge for Premium. A free account, and a closed or starting engine
  // (nothing known yet), show neither.
  readonly property bool showSignIn: svc ? svc.ready && !svc.signedIn && !svc.signingIn : false
  readonly property bool showPremium: svc ? svc.ready && svc.premium : false

  spacing: Style.space(4)

  Logo {
    visible: root.showLeft
    objectName: "brandLogo"
    anchors.verticalCenter: parent.verticalCenter
    size: Style.font.body + Style.space(4)
    rim: root.foreground
  }
  Text {
    visible: root.showLeft
    anchors.verticalCenter: parent.verticalCenter
    opacity: 0.85
    text: "Solfa"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold
  }
  Rectangle {
    id: premium
    objectName: "premiumBadge"
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showLeft && root.showPremium
    width: premiumText.implicitWidth + Style.space(12)
    height: premiumText.implicitHeight + Style.space(4)
    radius: height / 2
    color: Util.alpha(Calm.accent, 0.16)
    border.width: 1
    border.color: Util.alpha(Calm.accent, 0.4)
    Text {
      id: premiumText
      anchors.centerIn: parent
      text: "Premium"
      textFormat: Text.PlainText
      color: Calm.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
  HitButton {
    id: signIn
    objectName: "signInButton"
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
    objectName: "gearButton"
    anchors.verticalCenter: parent.verticalCenter
    minSize: Style.space(28)
    iconText: Icons.gear
    iconSize: Style.font.body
    foreground: root.settingsOpen ? Calm.accent : root.foreground
    selected: root.settingsOpen
    visible: root.showRight && root.reachable
    opacity: root.settingsOpen || hot ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    tooltipText: "Settings"
    onClicked: root.gearClicked()
  }
  HitButton {
    id: power
    objectName: "powerButton"
    anchors.verticalCenter: parent.verticalCenter
    minSize: Style.space(28)
    iconText: Icons.power
    iconSize: Style.font.body
    foreground: root.closed ? Calm.accent : root.foreground
    selected: root.closed
    visible: root.showRight && root.reachable
    opacity: root.closed || hot ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    tooltipText: root.closed ? "Turn Solfa on" : "Turn Solfa off — the music stops"
    onClicked: if (root.svc) root.svc.toggleEngine()
  }
}
