import QtQuick

// Icon, a sentence, and optionally one action. The icon floats gently.
Item {
  id: e
  property string icon: "album"
  property string title: ""
  property string body: ""
  property string action: ""
  property string actionIcon: ""
  property color tone: Theme.accent
  property bool busy: false
  property bool go: true
  signal clicked()
  Column {
    anchors.centerIn: parent
    width: Math.min(300, parent.width)
    spacing: 10
    opacity: e.go ? 1 : 0
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 300 } }
    Item {
      width: 76; height: 76; anchors.horizontalCenter: parent.horizontalCenter
      Glow { anchors.centerIn: parent; width: 160; height: 160; color: e.tone; strength: 0.34 }
      Rectangle { id: badge; anchors.centerIn: parent; width: 64; height: 64; radius: 22; color: Theme.a(e.tone, 0.14); border.width: 1; border.color: Theme.a(e.tone, 0.4)
        SequentialAnimation on y { running: !Motion.reduce; loops: Animation.Infinite; NumberAnimation { to: 6; duration: 1900; easing.type: Easing.InOutSine } NumberAnimation { to: 12; duration: 1900; easing.type: Easing.InOutSine } }
        Icon { anchors.centerIn: parent; name: e.icon; size: 28; color: e.tone }
        Spinner { visible: e.busy; anchors.centerIn: parent; size: 64; color: e.tone } }
    }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: e.title; color: Theme.fg; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold; wrapMode: Text.WordWrap }
    Text { visible: e.body !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: e.body; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.WordWrap }
    Item { visible: e.action !== ""; width: 1; height: 6 }
    Btn { visible: e.action !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: e.action; icon: e.actionIcon; kind: e.tone === Theme.err ? "quiet" : "primary"; onClicked: e.clicked() }
  }
}
