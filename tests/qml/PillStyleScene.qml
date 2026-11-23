import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Design study (not a test): the closed bar pill in four looks, on a light or a dark
// bar stub, rendered offscreen by tests/pill_options.py, which writes the theme files
// (Omarchy "white" light, "tokyo-night" dark) into the isolated HOME. Env: SOLFA_THEME, SOLFA_COVER (a picture), SOLFA_OUT_DIR (where bar-<style>.png go). Logs one
// "PILL {...}" line with the colours each look paints, for the contrast numbers.
ShellRoot {
  id: scene
  readonly property bool lightTheme: Quickshell.env("SOLFA_THEME") === "light"
  readonly property var styles: ["solid", "outline", "tint", "glass", "hover"]

  QtObject {
    id: svc
    property bool closed: false
    property bool bridgeUp: true
    property bool signingIn: false
    property bool ready: true
    property bool hasTrack: true
    property bool isPlaying: true
    property bool isAd: false
    property bool signedIn: true
    property string title: "Reise, Reise"
    property string artist: "Rammstein"
    property string album: "Reise, Reise"
    property string engineLine: ""
    property string thumb: Quickshell.env("SOLFA_COVER")
    property real duration: 214
    property real position: 83
    property real progress: 0.39
    property int volume: 60
    property bool muted: false
    property var settings: ({})
    property int fastClockUsers: 0
    function startEngine() {}
    function togglePlaying() {}
    function previous() {}
    function next() {}
  }
  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Commons.Color.bar.text
    property string fontFamily: Style.font.family
    property var shell: QtObject { function serviceFor(id) { return svc } }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 260
    implicitHeight: 5 * 34
    visible: true
    color: Commons.Color.bar.background

    Column {
      id: stage
      anchors.fill: parent
      spacing: 8
      Repeater {
        model: scene.styles
        delegate: Rectangle {
          required property string modelData
          required property int index
          objectName: "bar" + index
          width: 260; height: 26
          color: Commons.Color.bar.background
          SolfaBar { id: w; bar: fakeBar; pillStyle: modelData; anchors.centerIn: parent }
          property alias w: w
        }
      }
    }

    function find(name) {
      for (var i = 0; i < stage.children.length; i++) if (stage.children[i].objectName === name) return stage.children[i]
      return null
    }

    Timer {
      interval: 1200
      running: true
      onTriggered: {
        var info = {}
        var left = scene.styles.length
        for (var i = 0; i < scene.styles.length; i++) {
          (function (i) {
            var bar = win.find("bar" + i)
            var f = bar.w.pillFill, b = bar.w.barBg, ink = bar.w.fg
            info[scene.styles[i]] = { fill: [f.r, f.g, f.b, f.a], bar: [b.r, b.g, b.b, b.a], ink: [ink.r, ink.g, ink.b, ink.a], outlined: bar.w.pillOutlined }
            bar.grabToImage(function (r) {
              r.saveToFile(Quickshell.env("SOLFA_OUT_DIR") + "/bar-" + scene.styles[i] + ".png")
              if (--left === 0) { console.log("PILL " + JSON.stringify(info)); Qt.quit() }
            })
          })(i)
        }
      }
    }
  }
}
