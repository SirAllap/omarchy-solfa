import QtQuick
import "../lib"
import qs.Ui
import qs.Commons

// A soft blob that squishes and wobbles while something loads (after css-loaders' "squishy").
// Reduce motion: it stays still.
Item {
  id: root
  property real size: 28
  property color color: Calm.accent
  property bool running: visible
  width: size
  height: size

  Rectangle {
    id: blob
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.color
    antialiasing: true
    transform: Scale { id: sq; origin.x: blob.width / 2; origin.y: blob.height / 2; xScale: 1; yScale: 1 }
  }

  SequentialAnimation {
    running: root.running && !Style.reduceMotion
    loops: Animation.Infinite
    ParallelAnimation {
      NumberAnimation { target: sq; property: "xScale"; to: 1.22; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { target: sq; property: "yScale"; to: 0.78; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { target: blob; property: "rotation"; to: 90; duration: 400; easing.type: Easing.InOutSine }
    }
    ParallelAnimation {
      NumberAnimation { target: sq; property: "xScale"; to: 0.82; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { target: sq; property: "yScale"; to: 1.18; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { target: blob; property: "rotation"; to: 180; duration: 400; easing.type: Easing.InOutSine }
    }
    ScriptAction { script: blob.rotation = 0 }
  }
}
