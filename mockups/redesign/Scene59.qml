import QtQuick
HostWindow {
  cw: 560; ch: 330; settleMs: 1200
  Rectangle { anchors.fill: parent; radius: 26; color: Theme.surface; border.width: 1; border.color: Theme.hair }
  Row { x: 40; y: 40; spacing: 50
    Item { width: 200; height: 200
      DotRing { anchors.centerIn: parent; size: 200; dots: 56; value: 0.62 }
      Cover { anchors.centerIn: parent; width: 150; height: 150; round: true; seed: 0; breathe: true; playing: true } }
    Column { spacing: 14
      Row { spacing: 14; Item { width: 68; height: 68; DotRing { anchors.centerIn: parent; size: 68; value: 0.42 } Cover { anchors.centerIn: parent; width: 52; height: 52; round: true; seed: 0 } }
        Item { width: 68; height: 68; DotRing { anchors.centerIn: parent; size: 68; value: 0.72; from: Theme.ok; to: "#8fd3ff" } Cover { anchors.centerIn: parent; width: 52; height: 52; round: true; seed: 0 } } }
      Text { text: "Progress (violet to pink)\nVolume (green to blue)"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
      Row { spacing: 14; Repeater { model: [34, 30, 26, 22]; Item { width: modelData; height: modelData; DotRing { anchors.centerIn: parent; size: modelData; value: 0.5 } } } }
      Text { text: "Bar sizes 34, 30, 26, 22"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 } } }
}
