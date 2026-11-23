import QtQuick

// mode: playlists | songs | albums | artists | signedout | loading | error
Item {
  id: v
  property string mode: "playlists"
  property bool active: true
  readonly property var sections: [["playlists", "Playlists"], ["songs", "Liked songs"], ["albums", "Albums"], ["artists", "Artists"]]
  readonly property bool shown: mode !== "signedout"
  Row { id: chips; spacing: 6; visible: v.shown
    Repeater { model: v.sections; Chip { text: modelData[1]; on: v.mode === modelData[0] } } }
  Grid { y: 44; columns: 3; spacing: 12; visible: v.mode === "playlists" || v.mode === "albums"; columnSpacing: 12; rowSpacing: 10
    Repeater { model: 6; GridCard { go: v.active && (v.mode === "playlists" || v.mode === "albums"); index: modelData; width: (v.width - 24) / 3; height: width + 38; item: Fake.playlists[modelData]; hot: modelData === 1 } } }
  Grid { y: 44; columns: 2; spacing: 12; visible: v.mode === "artists"; columnSpacing: 12; rowSpacing: 4; width: parent.width
    Repeater { model: 4; GridCard { go: v.active && v.mode === "artists"; index: modelData; round: true; width: (v.width - 12) / 2; height: 134; item: Fake.artists[modelData]; hot: modelData === 0 } } }
  Column { y: 40; width: parent.width; visible: v.mode === "songs"
    Repeater { model: 5; TrackRow { go: v.active && v.mode === "songs"; index: modelData; track: Fake.tracks[modelData]; meta: Fake.tracks[modelData].a + " · " + Fake.tracks[modelData].al; hot: modelData === 1 } } }
  Column { y: 44; width: parent.width; visible: v.mode === "loading"
    Row { spacing: 12; Repeater { model: 3; Column { spacing: 6; Skeleton { width: (v.width - 24) / 3; height: width; radius: 16 } Skeleton { width: 80; height: 12 } Skeleton { width: 50; height: 10 } } } } }
  EmptyState { anchors.fill: parent; visible: v.mode === "signedout"; go: v.active; icon: "user"; title: "Sign in to see your library"; body: "Playlists, liked songs and albums need your YouTube Music account. Search and play work without it."; action: "Sign in"; actionIcon: "user" }
  EmptyState { anchors.fill: parent; visible: v.mode === "error"; go: v.active; icon: "warn"; tone: Theme.err; title: "Could not load your library"; body: "Showing what we have. Pull again in a moment."; action: "Try again"; actionIcon: "repeat" }
  Chip { visible: v.mode === "error"; text: "Playlists"; on: true; x: 0; y: 0 }
}
