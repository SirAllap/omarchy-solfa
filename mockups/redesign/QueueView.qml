import QtQuick

// mode: normal | empty | loading | error
Item {
  id: v
  property string mode: "normal"
  property bool active: true
  Item {
    visible: v.mode === "normal" || v.mode === "loading"
    width: parent.width; height: 26
    Text { anchors.verticalCenter: parent.verticalCenter; x: 4; text: "UP NEXT"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    Text { anchors.verticalCenter: parent.verticalCenter; x: 70; text: v.mode === "loading" ? "" : "8 songs · 29 min"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
    Btn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; compact: true; kind: "ghost"; icon: "trash"; text: "Clear" }
  }
  Column { y: 30; width: parent.width; visible: v.mode === "normal"
    Repeater { model: 5
      TrackRow { go: v.active; index: modelData; track: Fake.tracks[modelData]; current: modelData === 0; playing: true; hot: modelData === 2; selected: modelData === 1; removable: true } } }
  SkeletonRows { y: 30; width: parent.width; visible: v.mode === "loading"; count: 5 }
  EmptyState { anchors.fill: parent; visible: v.mode === "empty"; go: v.active; icon: "queue"; title: "The queue is empty"; body: "Add songs from Search or Library, or start a radio from any song."; action: "Search for music"; actionIcon: "search" }
  EmptyState { anchors.fill: parent; visible: v.mode === "error"; go: v.active; icon: "warn"; tone: Theme.err; title: "Could not load the queue"; body: "YouTube Music did not answer. Your songs are safe."; action: "Try again"; actionIcon: "repeat" }
}
