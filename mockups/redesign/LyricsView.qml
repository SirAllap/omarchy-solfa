import QtQuick

// mode: synced | plain | none | loading
Item {
  id: v
  property string mode: "synced"
  property bool active: true
  property int cur: 3
  clip: true
  readonly property int lineH: 46
  Row { id: tag; visible: v.mode === "synced" || v.mode === "plain"; spacing: 8; z: 3
    Rectangle { height: 22; width: tt.width + 18; radius: 11; color: Theme.a(Theme.ok, 0.14); border.width: 1; border.color: Theme.a(Theme.ok, 0.4)
      Text { id: tt; anchors.centerIn: parent; text: v.mode === "synced" ? "Synced" : "Plain text"; color: Theme.ok; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold } }
    Text { anchors.verticalCenter: parent.verticalCenter; text: v.mode === "synced" ? "follows the song · j k scroll" : "j k scroll"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 } }
  Item { id: stage; y: 30; width: parent.width; height: parent.height - 30; visible: v.mode === "synced"
    Glow { x: 0; y: stage.height / 2 - 70; width: stage.width; height: 140; color: Theme.accent; strength: 0.16 }
    Column { id: col; width: parent.width
      y: stage.height / 2 - (v.cur * v.lineH + v.lineH / 2)
      Behavior on y { enabled: !Motion.reduce; NumberAnimation { duration: Motion.scrollMs; easing.type: Easing.InOutCubic } }
      Repeater { model: Fake.lyrics
        Item { width: col.width; height: v.lineH
          readonly property real dist: Math.abs(index - v.cur)
          Typewriter { id: ln; x: 4; width: parent.width - 8; anchors.verticalCenter: parent.verticalCenter; text: modelData; maxLines: 1; typing: dist === 0 && v.active
            color: dist === 0 ? Theme.fg : Theme.dim
            weight: dist === 0 ? Font.Bold : Font.DemiBold; pixelSize: dist === 0 ? 22 : 18
            opacity: Math.max(0.16, 1 - dist * 0.3)
            Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 320 } }
            Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 320 } } } } } }
    Rectangle { anchors.top: parent.top; width: parent.width; height: 50; gradient: Gradient { GradientStop { position: 0; color: Theme.surface } GradientStop { position: 1; color: "transparent" } } }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 50; gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Theme.surface } } }
  }
  Column { y: 34; width: parent.width; spacing: 9; visible: v.mode === "plain"
    Repeater { model: Fake.lyrics; Text { width: parent.width; text: modelData; elide: Text.ElideRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: 15 } } }
  EmptyState { anchors.fill: parent; visible: v.mode === "none"; go: v.active; icon: "lyrics"; title: "No lyrics for this song"; body: "YouTube Music has none for “Glass Harbour”. Enjoy the music." }
  Column { y: 40; width: parent.width; spacing: 16; visible: v.mode === "loading"
    Repeater { model: 6; Skeleton { width: 200 + (index * 53) % 190; height: 18; radius: 9 } } }
}
