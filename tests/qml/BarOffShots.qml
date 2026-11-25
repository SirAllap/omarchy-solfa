import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "views" as Views
import "lib"

// The PR screenshots of the Off state (#33), made from the real QML: the bar pill off (at rest and
// hovered) and the panel's Off view (at rest, hovered, and with no last song), each saved as its own
// PNG in $SOLFA_SHOT_OUT. An INVENTED song; the cover is the generated gradient in $SOLFA_SHOT_COVER.
// Run by tests/bar_off_shots.py (offscreen, QT_SCALE_FACTOR=2). Never the live desktop.
ShellRoot {
  id: scene
  property int pending: 0

  component FakeSvc: QtObject {
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: !closed
    property bool hasTrack: !closed
    property bool isPlaying: !closed
    property bool isAd: false
    property bool adSkippable: false
    property bool signedIn: true
    property string panelKeyLabel: "Super+Shift+M"
    property var panelKeyChosen: ({ keys: "SUPER + SHIFT + M" })
    property var playPauseKeyChosen: ({ keys: "SUPER + ALT + P" })
    property string playPauseKeyLabel: "Super+Alt+P"
    property var panelKeyOptions: ["", "SUPER + SHIFT + M"]
    property bool premium: false
    property string like: "LIKE"
    property string title: hasTrack ? "Northern Lights" : ""
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: closed ? "Solfa is off" : ""
    property string thumb: ""
    property string lastTitle: ""
    property string lastThumb: ""
    property string lastArtist: ""
    property string lastAlbum: ""
    property real lastPosition: -1
    property real lastDuration: 0
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property string repeatMode: "ALL"
    property int volume: 60
    property bool muted: false
    property string videoId: hasTrack ? "v1" : ""
    property var engine: ({ status: closed ? "stopped" : "ready", wantRunning: !closed })
    property var calls: []
    property var settings: ({})
    property int fastClockUsers: 0
    function toggleEngine() { calls.push("toggleEngine") }
    function startEngine() { calls.push("startEngine") }
    function startAndPlay() { calls.push("startAndPlay") }
    function togglePlaying() { calls.push("togglePlaying") }
    function previous() {}
    function next() {}
    function toggleLike() {}
    function skipAd() {}
    function seek(v) {}
    function shuffle() {}
    function cycleRepeat() {}
    function toggleMute() {}
    function setVolume(v) {}
  }

  FakeSvc { id: shotSvc; closed: true; lastTitle: "Glass Harbour"; lastArtist: "The Quiet Tides"; lastAlbum: "Low Light"
    lastPosition: 102; lastDuration: 238; lastThumb: "file://" + Quickshell.env("SOLFA_SHOT_COVER") }
  FakeSvc { id: bareSvc; closed: true }

  component FakeBar: QtObject {
    property var svc: null
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property var shell: QtObject { function serviceFor(id) { return svc } }
    property string tip: ""
    function showTooltip(item, text) { tip = text }
    function hideTooltip(item) {}
  }

  FakeBar { id: shotBar; svc: shotSvc }

  function save(item, name) {
    scene.pending++
    item.grabToImage(function (r) {
      r.saveToFile(Quickshell.env("SOLFA_SHOT_OUT") + "/" + name)
      scene.pending--
      console.log("SHOT " + name)
    })
  }

  component PanelCard: Rectangle {
    property alias svcRef: off.svc
    property alias offCard: off
    width: 460
    height: head.height + off.implicitHeight + 24 + 28
    radius: 18
    clip: true
    color: Calm.surface
    border.width: 1
    border.color: Calm.hair
    Views.BrandCorner { id: head; x: 24; y: 20; showRight: false; svc: off.svc }
    Views.OffCard { id: off; x: 24; y: head.height + 24; width: parent.width - 48; bar: shotBar }
  }

  FloatingWindow {
    id: win
    implicitWidth: 1100
    implicitHeight: 760
    visible: true
    color: Color.popups.background

    TestCase { id: tc; name: "shots"; when: false }

    Item {
      id: stage
      anchors.fill: parent
      Row {
        x: 20; y: 16; spacing: 20
        Rectangle { id: barRestBox; width: 220; height: 34; color: Color.bar ? Color.bar.background : "#101014"
          SolfaBar { id: barRest; bar: shotBar; anchors.centerIn: parent } }
        Rectangle { id: barHoverBox; width: 220; height: 34; color: Color.bar ? Color.bar.background : "#101014"
          SolfaBar { id: barHover; bar: shotBar; anchors.centerIn: parent } }
      }
      Row {
        x: 20; y: 70; spacing: 20
        PanelCard { id: restCard; svcRef: shotSvc }
        PanelCard { id: hoverCard; svcRef: shotSvc }
        PanelCard { id: bareCard; svcRef: bareSvc }
      }
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) { var f = find(item.children[i], name); if (f) return f }
      return null
    }

    Timer {
      interval: 1200; running: true
      onTriggered: {
        scene.save(barRestBox, "01-bar-off-rest.png")
        scene.save(restCard, "03-panel-off-rest.png")
        scene.save(bareCard, "05-panel-off-no-song.png")
        tc.mouseMove(barHover, 2, 2)
        tc.mouseMove(barHover, barHover.pillBoxX + barHover.pillBoxW / 2, barHover.height / 2)
        step2.start()
      }
    }
    Timer {
      id: step2; interval: 600
      onTriggered: {
        scene.save(barHoverBox, "02-bar-off-hover.png")
        step2b.start()
      }
    }
    // The grab renders on the next frame: the pointer moves on only after it.
    Timer {
      id: step2b; interval: 500
      onTriggered: {
        var cv = win.find(hoverCard, "offCover")
        tc.mouseMove(cv, cv.width / 2, cv.height / 2)
        step3.start()
      }
    }
    Timer {
      id: step3; interval: 900
      onTriggered: { scene.save(hoverCard, "04-panel-off-hover.png"); done.start() }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.quit() }
    Timer { id: done; interval: 1500; onTriggered: Qt.quit() }
  }
}
