import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "views" as Views

// Solfa running and closed, rendered once offscreen by a private
// Quickshell (test_closed.py): the bar pill playing and closed, and the
// panel's top (song, name, power button) running, with the pointer on the
// power button, and closed. Saves a picture to $SOLFA_SCENE_OUT and logs
// what the widgets show as one "STATE {...}" line.
ShellRoot {
  property var asleepRest: ({})
  property var asleepAwake: ({})
  property var offClicks: ({})
  property var clicksLog: ({})
  id: scene

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
  FakeSvc { id: runningSvc }
  FakeSvc { id: closedSvc; closed: true }
  FakeSvc { id: asleepSvc; closed: true; lastTitle: "Northern Lights"; lastArtist: "The Examples" }
  FakeSvc { id: offSvc; closed: true; lastTitle: "Northern Lights"; lastArtist: "The Examples" }
  FakeSvc { id: offBareSvc; closed: true; signedIn: false; property bool signInWhenUp: false }

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
  FakeBar { id: runningBar; svc: runningSvc }
  FakeBar { id: closedBar; svc: closedSvc }
  FakeBar { id: asleepBar; svc: asleepSvc }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 800
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent
      Rectangle { anchors.fill: parent; color: Color.popups.background }

      Column {
        x: 20; y: 16
        width: 600
        spacing: 12

        Text { text: "Bar: playing / closed"; color: Color.foreground; opacity: 0.5; font.pixelSize: 11 }
        Row {
          spacing: 12
          Rectangle {
            width: 190; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SolfaBar { id: barRunning; bar: runningBar; anchors.centerIn: parent }
          }
          Rectangle {
            width: 190; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SolfaBar { id: barClosed; bar: closedBar; anchors.centerIn: parent }
          }
          Rectangle {
            width: 190; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SolfaBar { id: barAsleep; bar: asleepBar; anchors.centerIn: parent }
          }
        }

        Row {
          spacing: 12
          Views.OffCard { id: offSong; objectName: "offSong"; width: 280; svc: offSvc }
          Views.OffCard { id: offBare; objectName: "offBare"; width: 280; svc: offBareSvc; property var tabs: []; onTabRequested: function (k) { tabs = tabs.concat([k]) } }
        }

        Text { text: "Panel top: running / pointer on power / closed"; color: Color.foreground; opacity: 0.5; font.pixelSize: 11 }
        Repeater {
          model: [runningSvc, runningSvc, closedSvc]
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: 600; height: 104; radius: 10
            color: Color.popups.background
            border.color: Qt.rgba(1, 1, 1, 0.08)
            Views.NowPlaying {
              anchors.top: parent.top; anchors.topMargin: 12
              anchors.left: parent.left; anchors.leftMargin: 16
              anchors.right: parent.right; anchors.rightMargin: 16
              svc: modelData
              reserveRight: corner.width
            }
            Views.BrandCorner {
              id: corner
              objectName: "corner" + index
              anchors.top: parent.top; anchors.topMargin: 12
              anchors.right: parent.right; anchors.rightMargin: 8
              svc: modelData
            }
          }
        }
      }
    }

    TestCase {
      id: tc
      name: "closed"
      when: false
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }

    Timer {
      interval: 900
      running: true
      onTriggered: {
        var c1 = win.find(stage, "corner1")
        var btn = win.find(c1, "powerButton")
        asleepRest = { label: barAsleep.label, italic: win.find(barAsleep, "barTitle").font.italic, opacity: win.find(barAsleep, "barTitle").opacity, mark: barAsleep.showMark }
        tc.mouseMove(barAsleep, barAsleep.pillBoxX + barAsleep.pillBoxW / 2, barAsleep.height / 2)
        awakeCheck.start()
      }
    }
    // The pointer sits on the asleep pill first; its woken look is read, then the pointer moves on.
    Timer {
      id: awakeCheck
      interval: 300
      onTriggered: {
        var t = win.find(barAsleep, "barTitle")
        asleepAwake = { awake: barAsleep.awake, italic: t.font.italic, opacity: t.opacity, tip: asleepBar.tip }
        var btn = win.find(win.find(stage, "corner1"), "powerButton")
        tc.mouseMove(btn, btn.width / 2, btn.height / 2)
        hoverDone.start()
      }
    }
    Timer {
      id: hoverDone
      interval: 400
      onTriggered: {
        var c2 = win.find(stage, "corner2")
        var btn = win.find(c2, "powerButton")
        console.log("STATE " + JSON.stringify({
          barRunning: { label: barRunning.label, controls: barRunning.showControls, opacity: barRunning.children.length },
          barAsleep: { rest: asleepRest, awake: asleepAwake, asleepSong: barAsleep.asleepSong, bareMark: barClosed.showMark, bareAsleep: barClosed.asleepSong },
          barClosed: { label: barClosed.label, controls: barClosed.showControls, closed: barClosed.closed, w: barClosed.pillBoxW, minW: barClosed.pillMinW },
          powerClosed: { visible: btn.visible },
          powerHover: { hot: win.find(win.find(stage, "corner1"), "powerButton").hot }
        }))
        // OFF + a click on the bar pill: the panel opens, the engine is not asked to start.
        var rb = barRunning, cb = barClosed
        tc.mouseClick(cb, cb.pillBoxX + cb.pillBoxW / 2, cb.height / 2)
        pillClick.start()
      }
    }
    Timer {
      id: offHover
      interval: 300
      onTriggered: {
        console.log("CLICKS " + JSON.stringify(scene.clicksLog))
        console.log("OFFCARD " + JSON.stringify({
          song: { visible: offSong.hasLast, calls: scene.offClicks.calls, awake: offSong.awake,
            title: win.find(offSong, "offLastTitle").text, artist: win.find(offSong, "offLastArtist").text,
            note: win.find(offSong, "offNote").text, power: !!win.find(offSong, "offPower") || win.find(offSong, "offFirstRun").visible,
            play: win.find(offSong, "offCoverPlay").opacity, asleep: win.find(offSong, "offCover").asleep },
          bare: { hasLast: offBare.hasLast, record: win.find(offBare, "offRecord").visible, welcome: win.find(offBare, "offFirstRun").visible, signIn: win.find(offBare, "offSignIn").visible, song: win.find(offBare, "offLast").visible }
        }))
        stage.grabToImage(function (r) {
          r.saveToFile(Quickshell.env("SOLFA_SCENE_OUT"))
          Qt.quit()
        })
      }
    }
    Timer {
      id: pillClick
      interval: 1500
      onTriggered: {
        console.log("PILLCLICK " + JSON.stringify({ opened: barClosed.opened, calls: closedSvc.calls.slice() }))
        // The welcome card: the record starts Solfa on Search; a chip starts it on its own tab.
        var rec = win.find(offBare, "offRecord"), lib = win.find(offBare, "offChip_library")
        tc.mouseClick(rec, rec.width / 2, rec.height / 2)
        tc.mouseClick(lib, lib.width / 2, lib.height / 2)
        var clicks = { bare: offBareSvc.calls.slice(), tabs: offBare.tabs.slice() }
        // The panel's Off view with a last song: a click on the cover is Play on.
        var cv = win.find(offSong, "offCover")
        tc.mouseClick(cv, cv.width / 2, cv.height / 2)
        var after = offSvc.calls.slice()
        tc.mouseMove(cv, 5, 5)
        offHover.start()
        scene.offClicks = { calls: after }
        scene.clicksLog = clicks
      }
    }
  }
}
