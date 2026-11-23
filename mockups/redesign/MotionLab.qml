import QtQuick

// Each motion idea on its own, looping, with fake data. Ideas only, taken from
// a study of the MIT project HANCORE-linux/rumb; no code or assets copied.
Item {
  id: lab
  width: 5 * 300 + 4 * 14
  height: 2 * 250 + 14
  property int beat: 0
  Timer { interval: 1500; running: true; repeat: true; onTriggered: lab.beat++ }

  Grid {
    columns: 5; spacing: 14

    // 1. the cover glances at the control just used (critically damped spring)
    LabTile { title: "1  Cover looks at the control"; note: "Press a control and the cover leans toward it on a critically damped spring (omega about 11). A new press while it moves never jumps."
      Cover { id: covA; x: 106; y: 4; width: 88; height: 88; radius: 20; seed: 3; breathe: true; playing: true; lit: true }
      Row { x: 60; y: 106; spacing: 10
        Repeater { id: gr; model: ["prev", "play", "next", "heart"]
          IconButton { icon: modelData; size: 34; glyph: 16; hot: lab.beat % 4 === index; filled: modelData === "heart" } } }
      Connections { target: lab; function onBeatChanged() {
        var it = gr.itemAt(lab.beat % 4); var p = it.mapToItem(covA.parent, it.width / 2, it.height / 2)
        var dx = p.x - (covA.x + 44), dy = p.y - (covA.y + 44), L = Math.max(1, Math.hypot(dx, dy))
        covA.gx = dx / L * 8; covA.gy = dy / L * 8 } } }

    // 2. event glows: colour = meaning, fade exp(-t/520 ms)
    LabTile { title: "2  Glows that mean something"; note: "Like is pink, queue is green, error is red, new song is white-blue. Glow fades as exp(-t/520 ms), the flash as exp(-t/380 ms)."
      Repeater { model: [["like", 60], ["queue", 150], ["error", 240]]
        Item { x: modelData[1]; y: 56
          EventGlow { id: eg; size: 150 }
          Rectangle { x: -18; y: -18; width: 36; height: 36; radius: 18; color: Theme.a(Motion.eventColor(modelData[0]), 0.25); border.width: 1; border.color: Motion.eventColor(modelData[0]) }
          Text { x: -30; y: 30; width: 60; horizontalAlignment: Text.AlignHCenter; text: modelData[0]; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 }
          Connections { target: lab; function onBeatChanged() { if (lab.beat % 3 === index) eg.fire(modelData[0]) } } } } }

    // 3. idle life: breathing, then a glance elsewhere
    LabTile { id: t3; title: "3  Life while idle"; note: "The cover breathes while music plays. After a quiet spell (8 s in the app, 2.5 s here) it looks elsewhere, then rests."
      Cover { id: ic; x: 106; y: 24; width: 88; height: 88; radius: 20; seed: 5; breathe: true; playing: true; lit: true }
      property int n: 1
      Timer { interval: 2500; running: true; repeat: true; onTriggered: { var a = Motion.rand(t3.n++ + 40) * 6.283; ic.gx = Math.cos(a) * 8; ic.gy = Math.sin(a) * 8; ib.restart() } }
      Timer { id: ib; interval: 520; onTriggered: { ic.gx = 0; ic.gy = 0 } } }

    // 4. comet: play next flies to the Queue tab
    LabTile { title: "4  Comet to the Queue"; note: "Play next sends a dot along a small arc to the Queue tab. It lands with a green glow. Arc height is seeded, so it repeats exactly."
      Rectangle { x: 18; y: 90; width: 120; height: 40; radius: 12; color: Theme.wash; border.width: 1; border.color: Theme.hair
        Text { anchors.centerIn: parent; text: "Slow Neon  +"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 } }
      Rectangle { x: 200; y: 18; width: 84; height: 34; radius: 17; color: Theme.a(Theme.accent, 0.2); border.width: 1; border.color: Theme.a(Theme.accent, 0.5)
        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "queue"; size: 16; color: Theme.accent }
        Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: "Queue"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold } }
      EventGlow { id: ce; x: 242; y: 35; size: 140 }
      Comet { id: cc; onArrived: ce.fire("queue") }
      Connections { target: lab; function onBeatChanged() { if (lab.beat % 2 === 0) cc.fly(78, 110, 242, 35, "next", lab.beat) } } }

    // 5. dot ring
    LabTile { id: t5; title: "5  Dot ring"; note: "Progress and volume as a ring of dots around the round cover of the bar widget. The head dot is bigger; the lit dots shimmer."
      property real v: 0.3
      NumberAnimation on v { from: 0.05; to: 0.97; duration: 6000; loops: Animation.Infinite }
      Row { x: 28; y: 14; spacing: 30
        Item { width: 100; height: 100
          DotRing { id: dr1; anchors.centerIn: parent; size: 100; dots: 40; value: t5.v }
          Cover { anchors.centerIn: parent; width: 76; height: 76; round: true; seed: 0; breathe: true; playing: true } }
        Column { spacing: 8; topPadding: 10
          Item { width: 34; height: 34; DotRing { anchors.centerIn: parent; size: 34; value: 0.42 } Cover { anchors.centerIn: parent; width: 26; height: 26; round: true; seed: 0 } }
          Item { width: 34; height: 34; DotRing { anchors.centerIn: parent; size: 34; value: 0.72; from: Theme.ok; to: "#8fd3ff" } Cover { anchors.centerIn: parent; width: 26; height: 26; round: true; seed: 0 } } } } }

    // 6. typewriter
    LabTile { title: "6  Typewriter"; note: "A new title or lyric line writes itself at 30 ms a letter, with a cursor that blinks every 530 ms. The space is reserved, so nothing jumps."
      Typewriter { x: 18; y: 30; width: 264; pixelSize: 21; weight: Font.Bold; text: Fake.tracks[(lab.beat >> 2) % 8].t }
      Typewriter { x: 18; y: 90; width: 264; pixelSize: 13; color: Theme.dim; maxLines: 1; text: Fake.tracks[(lab.beat >> 2) % 8].a + " · " + Fake.tracks[(lab.beat >> 2) % 8].al } }

    // 7. waves by priority
    LabTile { id: t7; title: "7  Waves by priority"; note: "On open, what matters arrives first: high at 0 ms, medium at 150 ms, low at 300 ms."
      property bool on: false
      Timer { interval: 2600; running: true; repeat: true; triggeredOnStart: true; onTriggered: { t7.on = false; wv.restart() } }
      Timer { id: wv; interval: 400; onTriggered: t7.on = true }
      Repeater { model: [["Now playing  (high, 0 ms)", 0], ["Song list  (medium, 150 ms)", 1], ["Key hints  (low, 300 ms)", 2]]
        WaveItem { x: 18; y: 12 + index * 44; width: 264; height: 36; priority: modelData[1]; go: t7.on
          Rectangle { width: 264; height: 36; radius: 12; color: Theme.a(Theme.accent, 0.12 + 0.05 * index); border.width: 1; border.color: Theme.a(Theme.accent, 0.35)
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12 } } } } }

    // 8. smoothstep scroll of lyrics
    LabTile { title: "8  Smooth lyric scroll"; note: "A new line eases in over 180 ms with smoothstep, x*x*(3-2x), and its text is typed."
      LyricsView { x: 18; y: 0; width: 264; height: 150; cur: (lab.beat % 8) + 1; mode: "synced"; active: true } }

    // 9. seeded variation
    LabTile { title: "9  Seeded randomness"; note: "Variation comes from a seed, so the same moment always looks the same and never shakes between frames."
      Row { x: 20; y: 18; spacing: 7; height: 110
        Repeater { model: 14
          Rectangle { width: 12; anchors.bottom: parent.bottom; radius: 6
            height: 14 + 90 * Motion.rand(index * 7 + ((lab.beat >> 1) % 6) * 101)
            color: Theme.hue(index, 0.6)
            Behavior on height { enabled: !Motion.reduce; NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } } } } } }

    // 10. one switch, and only while it matters
    LabTile { id: t10; title: "10  Reduce motion and gating"; note: "One global switch stops every loop and spring. Without it, decoration runs only while the panel is open and music plays."
      readonly property int phase: lab.beat % 6
      Cover { x: 24; y: 22; width: 70; height: 70; radius: 16; seed: 2; breathe: t10.phase < 2; playing: t10.phase < 2; lit: t10.phase < 2 }
      Column { x: 120; y: 20; spacing: 9
        Repeater { model: [["Panel open + playing", 0], ["Paused: all still", 1], ["Reduce motion: still", 2]]
          Row { spacing: 8; Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter
              color: Math.floor(lab.beat % 6 / 2) === modelData[1] ? Theme.ok : Qt.rgba(1, 1, 1, 0.2) }
            Text { text: modelData[0]; color: Math.floor(lab.beat % 6 / 2) === modelData[1] ? Theme.fg : Theme.faint; font.family: Theme.font; font.pixelSize: 12 } } } }
      Toggle { x: 24; y: 112; checked: t10.phase >= 4 } }
  }
}
