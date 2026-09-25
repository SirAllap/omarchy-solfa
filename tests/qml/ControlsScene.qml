import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "views" as Views
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons

// The panel's clickable controls with a fake service, rendered once
// offscreen by a private Quickshell (test_hit_targets.py): the song and its
// controls, the tabs, a queue with the cursor on a song, and the footer's
// "?". Saves a picture to $SOLFA_SCENE_OUT, logs every control's box as one
// "GEOM {...}" line, then clicks every control with a synthetic mouse and
// logs what each click did as one "CLICKS {...}" line.
ShellRoot {
  id: scene

  QtObject {
    id: fakeSvc
    property bool ready: true
    property bool hasTrack: true
    property bool isAd: false
    property bool signedIn: true
    property bool isPlaying: true
    property string like: "LIKE"
    property string title: "Northern Lights"
    property string artist: "The Examples"
    property string album: "Placeholder Skies"
    property string engineLine: ""
    property string thumb: ""
    property real duration: 214
    property real position: 83
    property string repeatMode: "ALL"
    property int volume: 60
    property bool muted: false
    property string videoId: "v1"
    property var calls: []
    function toggleLike() { calls.push("toggleLike") }
    function skipAd() {}
    function seek(v) {}
    function shuffle() { calls.push("shuffle") }
    function previous() { calls.push("previous") }
    function togglePlaying() { calls.push("togglePlaying") }
    function next() { calls.push("next") }
    function cycleRepeat() { calls.push("cycleRepeat") }
    function toggleMute() { calls.push("toggleMute") }
    function setVolume(v) {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 600
    implicitHeight: 560
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent

      Rectangle { anchors.fill: parent; color: Color.popups.background }

      Column {
        id: body
        x: 20; y: 20
        width: 560
        spacing: Style.space(14)

        Views.NowPlaying {
          id: hero
          width: parent.width
          svc: fakeSvc
        }

        Row {
          id: tabRow
          spacing: Style.space(4)
          Repeater {
            id: tabs
            model: [{ key: "queue", label: "Queue" }, { key: "search", label: "Search" }, { key: "library", label: "Library" }, { key: "lyrics", label: "Lyrics" }]
            delegate: Views.HitButton {
              required property var modelData
              text: modelData.label
              foreground: Color.foreground
              selected: modelData.key === "queue"
              onClicked: fakeSvc.calls.push("tab:" + modelData.key)
            }
          }
        }

        Views.RowList {
          id: list
          width: parent.width
          height: 4 * Style.space(46)
          rows: Model.queueRows({ index: 0, items: [
            { videoId: "v1", title: "Northern Lights", artist: "The Examples", duration: 214 },
            { videoId: "v2", title: "A Much Longer Song Title That Needs Every Pixel It Can Get", artist: "The Examples", duration: 187 },
            { videoId: "v3", title: "A Much Longer Song Title That Needs Every Pixel It Can Get", artist: "Sample Band", duration: 245 },
            { videoId: "v4", title: "Fourth Song", artist: "Sample Band", duration: 201 }] })
          cursor: 1
          playingId: "v1"
          onAction: function (name, i) { fakeSvc.calls.push("action:" + name + ":" + i) }
          onActivated: function (i) { fakeSvc.calls.push("row:" + i) }
          actionsFor: function (row) {
            if (!row || !row.item) return []
            var out = []
            if (row.queueIndex > 0) out.push({ name: "up", icon: Icons.up, tip: "Move up (K)" })
            if (row.queueIndex < 3) out.push({ name: "down", icon: Icons.down, tip: "Move down (J)" })
            if (!row.current) out.push({ name: "remove", icon: Icons.close, tip: "Remove (x)" })
            return out
          }
        }

        Item {
          id: footer
          width: parent.width
          height: Style.space(32)
          Views.HitButton {
            id: allKeysButton
            anchors.right: parent.right
            // "all keys" lines up with the edge: the box reaches into the card's
            // padding, never past it.
            anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
            anchors.verticalCenter: parent.verticalCenter
            width: allKeysSizer.implicitWidth + Style.space(16)
            onClicked: fakeSvc.calls.push("allKeys")
            Views.KeyHint { anchors.centerIn: parent; keys: "?"; label: "all keys" }
          }
          Views.KeyHint { id: allKeysSizer; visible: false; keys: "?"; label: "all keys" }
        }
      }
    }

    // Every HitButton on screen, and the width each queue title gets.
    function boxes(item, out) {
      for (var i = 0; i < item.children.length; i++) {
        var c = item.children[i]
        if (!c.visible) continue
        if (c.minSize !== undefined && c.iconOnly !== undefined) {
          var p = c.mapToItem(stage, 0, 0)
          out.buttons.push({ label: c.text || c.iconText, tip: c.tooltipText, x: p.x, y: p.y, w: c.width, h: c.height, shown: c.opacity > 0 })
        }
        if (c.elide === Text.ElideRight && c.font && c.font.pixelSize === Style.font.body && c.text.indexOf("Song") >= 0)
          out.titles.push({ text: c.text, w: c.width })
        win.boxes(c, out)
      }
      return out
    }

    // SOLFA_SCENE_STATES=1: a few buttons drawn as if the pointer were on
    // them, for the picture.
    function hover(item, n) {
      for (var i = 0; i < item.children.length; i++) {
        var c = item.children[i]
        if (c.minSize !== undefined && c.hasCursor !== undefined
            && (c.text === "Search" || c.tooltipText === "Next (n)" || c.tooltipText === "Like (f)"
                || (c.tooltipText === "Remove (x)" && c.opacity > 0) || (c.text === "" && c.iconText === "")))
          c.hasCursor = true
        win.hover(c)
      }
    }

    Timer {
      interval: 100
      running: Quickshell.env("SOLFA_SCENE_STATES") === "1"
      onTriggered: win.hover(stage)
    }

    function find(item, test) {
      for (var i = 0; i < item.children.length; i++) {
        var c = item.children[i]
        if (c.minSize !== undefined && c.visible && test(c)) return c
        var f = win.find(c, test)
        if (f) return f
      }
      return null
    }

    TestCase { id: mouse; when: false; name: "controls" }

    // Clicks each control in the middle and near a corner of its box (the
    // box is the target, not the glyph), and the spot of a hidden action.
    function clickAll() {
      var out = { clicked: {}, pressedScale: 0, releasedScale: 0 }
      var tips = ["Shuffle the queue (s)", "Previous (p)", "Pause (space)", "Next (n)", "Repeat all (r)",
                  "Mute (m)", "Remove the like (f)"]
      var targets = tips.map(function (t) { return [t, win.find(stage, function (c) { return c.tooltipText === t })] })
      ;["Queue", "Search", "Library", "Lyrics"].forEach(function (t) { targets.push([t, win.find(stage, function (c) { return c.text === t })]) })
      targets.push(["Remove (x)", win.find(list, function (c) { return c.tooltipText === "Remove (x)" && c.opacity > 0 })])
      targets.push(["?", allKeysButton])
      targets.forEach(function (t) {
        var b = t[1]
        var got = []
        if (b) {
          ;[[b.width / 2, b.height / 2], [3, 3], [b.width - 3, b.height - 3]].forEach(function (p) {
            var before = fakeSvc.calls.length
            mouse.mouseClick(b, p[0], p[1])
            got.push(fakeSvc.calls.slice(before).join(","))
          })
        }
        out.clicked[t[0]] = got
      })
      // A hidden action does nothing: the click lands on its row.
      var hidden = win.find(list, function (c) { return c.tooltipText === "Remove (x)" && c.opacity === 0 })
      var n = fakeSvc.calls.length
      if (hidden) mouse.mouseClick(hidden, hidden.width / 2, hidden.height / 2)
      out.hiddenClick = fakeSvc.calls.slice(n).join(",")
      // The pointer comes onto a row without the cursor, then onto its
      // Remove: it stays shown under the pointer, and the click removes.
      if (hidden) {
        list.cursor = 1   // the click above moved the cursor onto this row
        mouse.mouseMove(stage, 2, 2)
        mouse.wait(200)
        mouse.mouseMove(hidden, -Style.space(120), hidden.height / 2)
        mouse.wait(50)
        for (var step = 5; step >= 0; step--) {
          mouse.mouseMove(hidden, hidden.width / 2 - step * Style.space(20), hidden.height / 2)
          mouse.wait(30)
        }
        mouse.wait(200)
        out.hoverShown = hidden.opacity
        n = fakeSvc.calls.length
        mouse.mouseClick(hidden, hidden.width / 2, hidden.height / 2)
        out.hoverClick = fakeSvc.calls.slice(n).join(",")
      }
      // Pressed: the box shrinks a little; let go, it is back.
      var next = win.find(stage, function (c) { return c.tooltipText === "Next (n)" })
      mouse.mousePress(next, next.width / 2, next.height / 2)
      mouse.wait(250)
      out.pressedScale = next.scale
      mouse.mouseRelease(next, next.width / 2, next.height / 2)
      mouse.wait(250)
      out.releasedScale = next.scale
      return out
    }

    Timer {
      interval: 600
      running: true
      onTriggered: {
        console.info("GEOM " + JSON.stringify(win.boxes(stage, { buttons: [], titles: [], cursor: list.cursor })))
        stage.grabToImage(function (r) {
          r.saveToFile(Quickshell.env("SOLFA_SCENE_OUT"))
          if (Quickshell.env("SOLFA_SCENE_STATES") !== "1") console.info("CLICKS " + JSON.stringify(win.clickAll()))
          Qt.quit()
        })
      }
    }
  }
}
