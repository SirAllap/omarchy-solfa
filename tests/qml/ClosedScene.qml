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
  id: scene

  component FakeSvc: QtObject {
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: !closed
    property bool hasTrack: !closed
    property bool isPlaying: !closed
    property bool isAd: false
    property bool signedIn: true
    property bool premium: false
    property string like: "LIKE"
    property string title: hasTrack ? "Northern Lights" : ""
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: closed ? "Solfa is off" : ""
    property string thumb: ""
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property string repeatMode: "ALL"
    property int volume: 60
    property bool muted: false
    property string videoId: hasTrack ? "v1" : ""
    property var calls: []
    property var settings: ({})
    property int fastClockUsers: 0
    function toggleEngine() { calls.push("toggleEngine") }
    function startEngine() { calls.push("startEngine") }
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

  component FakeBar: QtObject {
    property var svc: null
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property var shell: QtObject { function serviceFor(id) { return svc } }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
  }
  FakeBar { id: runningBar; svc: runningSvc }
  FakeBar { id: closedBar; svc: closedSvc }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 470
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
          spacing: 16
          Rectangle {
            width: 280; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SolfaBar { id: barRunning; bar: runningBar; anchors.centerIn: parent }
          }
          Rectangle {
            width: 280; height: 26; color: Color.bar ? Color.bar.background : "#101014"
            SolfaBar { id: barClosed; bar: closedBar; anchors.centerIn: parent }
          }
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
          barClosed: { label: barClosed.label, controls: barClosed.showControls, closed: barClosed.closed },
          powerClosed: { tooltip: btn.tooltipText, selected: btn.selected, opacity: btn.opacity },
          powerHover: { hot: win.find(win.find(stage, "corner1"), "powerButton").hot }
        }))
        tc.mouseClick(btn, btn.width / 2, btn.height / 2)
        stage.grabToImage(function (r) {
          r.saveToFile(Quickshell.env("SOLFA_SCENE_OUT"))
          console.log("CLICKS " + JSON.stringify({ closed: closedSvc.calls }))
          Qt.quit()
        })
      }
    }
  }
}
