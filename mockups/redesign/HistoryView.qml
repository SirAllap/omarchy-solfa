import QtQuick

// mode: normal | empty | loading
Item {
  id: v
  property string mode: "normal"
  property bool active: true
  Column { width: parent.width; visible: v.mode === "normal"
    Text { x: 4; height: 26; text: "TODAY"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    Repeater { model: 2; TrackRow { go: v.active; index: modelData; track: Fake.tracks[modelData]; meta: Fake.tracks[modelData].a + " · " + ["now", "12 min ago"][modelData]; current: modelData === 0; hot: modelData === 1 } }
    Text { x: 4; height: 30; verticalAlignment: Text.AlignBottom; bottomPadding: 6; text: "YESTERDAY"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    Repeater { model: 2; TrackRow { go: v.active; index: modelData + 2; track: Fake.tracks[modelData + 4]; meta: Fake.tracks[modelData + 4].a + " · " + ["9:41 pm", "8:12 pm"][modelData] } }
  }
  SkeletonRows { y: 26; width: parent.width; visible: v.mode === "loading"; count: 4 }
  EmptyState { anchors.fill: parent; visible: v.mode === "empty"; go: v.active; icon: "history"; title: "Nothing played yet"; body: "Songs you play show up here, newest first." }
}
