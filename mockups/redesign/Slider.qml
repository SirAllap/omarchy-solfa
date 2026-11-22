import QtQuick

// A slim slider with a glowing fill and a knob that grows when held.
Item {
  id: s
  property real value: 0.5
  property bool hot: false
  property string labelRight: ""
  implicitWidth: 180
  implicitHeight: 26
  Rectangle { id: track; anchors.verticalCenter: parent.verticalCenter; width: parent.width - (s.labelRight ? 46 : 0); height: 5; radius: 3; color: Qt.rgba(1, 1, 1, 0.1)
    Rectangle { width: Math.max(5, s.value * parent.width); height: parent.height; radius: 3
      Behavior on width { enabled: !Motion.reduce; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } } }
    Glow { x: s.value * parent.width - width / 2; y: -width / 2 + 2.5; width: 34; height: 34; color: Theme.accent2; strength: s.hot || ma.pressed ? 0.6 : 0.3 }
    Rectangle { id: knob; width: 14; height: 14; radius: 7; color: "#fff"; y: -4.5; x: s.value * parent.width - 7
      scale: ma.pressed || s.hot ? 1.3 : 1
      Behavior on scale { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.001 } } }
  }
  Text { visible: s.labelRight !== ""; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: s.labelRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
  MouseArea { id: ma; anchors.fill: track; anchors.margins: -8; onPositionChanged: if (pressed) s.value = Math.max(0, Math.min(1, (mouseX - 8) / track.width)); onPressed: s.value = Math.max(0, Math.min(1, (mouseX - 8) / track.width)) }
}
