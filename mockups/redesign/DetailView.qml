import QtQuick

// A page opened from a list. kind: album | artist. mode: normal | loading | error
Item {
  id: v
  property string kind: "album"
  property string mode: "normal"
  property bool active: true
  readonly property bool artist: kind === "artist"
  Row { spacing: 8; height: 32
    Rectangle { width: bk.width + 24; height: 32; radius: 16; color: Theme.wash; border.width: 1; border.color: Theme.hair
      Row { id: bk; anchors.centerIn: parent; spacing: 4; Icon { name: "back"; size: 15; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter } Text { text: "Back"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } } }
    KeyCap { keys: "esc"; label: "back"; anchors.verticalCenter: parent.verticalCenter } }
  Item { visible: v.mode === "normal"; y: 44; width: parent.width; height: 130
    Cover { id: cv; width: 118; height: 118; radius: 20; round: v.artist; seed: v.artist ? 0 : 7; breathe: true; playing: true; lit: true }
    Column { x: 138; width: parent.width - 138; anchors.verticalCenter: cv.verticalCenter; spacing: 4
      Text { text: v.artist ? "ARTIST" : "ALBUM"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4 }
      Text { width: parent.width; text: v.artist ? "Nova Reyes" : "Low Tide Radio"; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.5 }
      Text { text: v.artist ? "2.4M listeners" : "Nova Reyes · 2024 · 12 songs · 41 min"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
      Row { spacing: 8; topPadding: 8
        Btn { kind: "primary"; icon: "play"; text: "Play" }
        Btn { icon: "shuffle"; text: "Shuffle" }
        IconButton { icon: "heart"; size: 36; glyph: 18 } } }
  }
  Column { visible: v.mode === "normal"; y: 182; width: parent.width
    Repeater { model: 3; TrackRow { go: v.active; index: modelData; track: Fake.tracks[[0, 7, 2][modelData]]; meta: v.artist ? "Low Tide Radio" : ""; hot: modelData === 1 } } }
  Column { visible: v.mode === "loading"; y: 44; width: parent.width; spacing: 14
    Row { spacing: 20; Skeleton { width: 118; height: 118; radius: 20 } Column { spacing: 10; topPadding: 20; Skeleton { width: 90; height: 11 } Skeleton { width: 190; height: 22 } Skeleton { width: 150; height: 12 } } }
    SkeletonRows { width: parent.width; count: 3 } }
  EmptyState { y: 40; width: parent.width; height: parent.height - 40; visible: v.mode === "error"; go: v.active; icon: "warn"; tone: Theme.err; title: "This page did not open"; body: "YouTube Music did not send it. Go back and try again."; action: "Try again"; actionIcon: "repeat" }
}
