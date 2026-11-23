import QtQuick

// Placeholder song rows while a list loads.
Column {
  id: s
  property int count: 4
  spacing: 0
  Repeater {
    model: s.count
    Item {
      width: s.width; height: 58
      Skeleton { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 42; height: 42; radius: 10 }
      Skeleton { x: 66; y: 14; width: 120 + (index * 37) % 90; height: 13; radius: 6 }
      Skeleton { x: 66; y: 34; width: 80 + (index * 29) % 60; height: 11; radius: 5 }
    }
  }
}
