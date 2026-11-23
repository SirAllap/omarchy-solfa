import QtQuick

// mode: idle | results | loading | empty | error
Item {
  id: v
  property string mode: "results"
  property bool active: true
  readonly property var kinds: ["All", "Songs", "Albums", "Artists", "Playlists", "Videos"]
  property int kind: 0
  SearchField { width: parent.width; text: v.mode === "idle" ? "" : (v.mode === "empty" ? "zzxq vell" : "glass"); focused: v.mode !== "idle"; busy: v.mode === "loading" }
  Row { y: 56; spacing: 6; visible: v.mode !== "idle"
    Repeater { model: v.kinds; Chip { text: modelData; on: index === v.kind; onClicked: v.kind = index } } }
  Column { y: 100; width: parent.width; visible: v.mode === "results"
    Repeater { model: 4
      TrackRow { go: v.active; index: modelData; track: Fake.tracks[[0, 3, 4, 7][modelData]]; meta: ["Song", "Song", "Album", "Song"][modelData] + " · " + Fake.tracks[[0, 3, 4, 7][modelData]].a; hot: modelData === 1; selected: modelData === 0 } } }
  SkeletonRows { y: 100; width: parent.width; visible: v.mode === "loading"; count: 4 }
  EmptyState { y: 70; width: parent.width; height: parent.height - 70; visible: v.mode === "empty"; go: v.active; icon: "search"; title: "No results for “zzxq vell”"; body: "Check the spelling, or try fewer words." }
  EmptyState { y: 70; width: parent.width; height: parent.height - 70; visible: v.mode === "error"; go: v.active; icon: "warn"; tone: Theme.err; title: "Search did not work"; body: "YouTube Music did not answer. Try again in a moment."; action: "Try again"; actionIcon: "repeat" }
  Item { visible: v.mode === "idle"; y: 62; width: parent.width; height: 240
    Text { text: "RECENT"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    Flow { y: 22; width: parent.width; spacing: 8
      Repeater { model: ["glass harbour", "lo-fi for focus", "orla vance live", "rainy day"]; Chip { icon: "history"; text: modelData; hot: index === 1 } } }
    Text { y: 110; text: "TRY"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    Flow { y: 132; width: parent.width; spacing: 8
      Repeater { model: ["New releases", "Chill", "Workout", "Focus", "Sleep"]; Chip { text: modelData } } }
  }
}
