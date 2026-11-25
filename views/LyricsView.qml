import QtQuick
import "../lib"
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// Lyrics for the song that plays. Timed lines follow the music; plain
// lyrics scroll by hand.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Calm.fg
  readonly property string family: Calm.font

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false
  property var lyrics: null
  property string forVideo: ""
  property bool busy: false
  property string error: ""
  readonly property bool timed: !!lyrics && lyrics.kind === "timed"
  readonly property int line: timed && svc ? Model.lyricIndex(lyrics.lines, svc.position * 1000 + 300) : -1
  readonly property var hints: [["j k", "scroll"], [", .", "seek"]]
  property int cursor: -1
  readonly property var current: null

  // Lines change every few seconds: ask the service for a finer clock
  // while timed lyrics are on screen.
  property bool usingFastClock: false
  readonly property bool wantsFastClock: active && timed && !!svc
  onWantsFastClockChanged: {
    if (!svc) return
    if (wantsFastClock && !usingFastClock) { svc.fastClockUsers += 1; usingFastClock = true }
    else if (!wantsFastClock && usingFastClock) { svc.fastClockUsers -= 1; usingFastClock = false }
  }
  Component.onDestruction: if (usingFastClock && svc) svc.fastClockUsers -= 1

  function shown() { load() }
  function move(dy) {
    if (timed) lines.contentY = Math.max(0, Math.min(lines.contentHeight - lines.height, lines.contentY + dy * 40))
    else plain.contentY = Math.max(0, Math.min(plain.contentHeight - plain.height, plain.contentY + dy * 40))
  }
  function activate() {}

  function load() {
    if (!svc || !svc.hasTrack) { view.lyrics = null; view.forVideo = ""; return }
    var vid = svc.videoId
    if (vid === view.forVideo && view.lyrics) return
    view.forVideo = vid
    view.busy = true
    view.error = ""
    view.lyrics = null
    svc.request("lyrics", { videoId: vid }, function (r) {
      if (vid !== view.forVideo) return
      view.busy = false
      if (r.ok) view.lyrics = r.data
      else view.error = Model.errorText(r.error)
    })
  }

  Connections {
    target: view.svc
    function onTrackChanged(v) { if (view.active) view.load() }
  }

  // The row's height goes in before the index: the view places the current
  // line by the range it has when the index changes.
  onLineChanged: if (timed && line >= 0) {
    curRow.text = lyrics.lines[line].text || " "
    lines.currentIndex = line
  }

  readonly property color ok: Qt.rgba(0.498, 0.647, 0.576, 1)
  readonly property color err: Qt.rgba(0.725, 0.439, 0.486, 1)
  readonly property int lineH: 46
  readonly property bool failed: !busy && error !== ""
  readonly property bool none: !busy && !failed && (!lyrics || lyrics.kind === "none")

  // No lyrics, or the lookup failed: the calm badge, a title and a sentence.
  Column {
    objectName: "lyricsState"
    anchors.centerIn: parent
    width: Math.min(300, parent.width - 40)
    visible: view.none || view.failed
    spacing: 10
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 64
      height: width
      radius: 22
      color: Calm.a(view.failed ? view.err : Calm.accent, 0.14)
      border.width: 1
      border.color: Calm.a(view.failed ? view.err : Calm.accent, 0.4)
      Text {
        anchors.centerIn: parent
        text: view.failed ? "!" : Icons.tabLyrics
        textFormat: Text.PlainText
        color: view.failed ? view.err : Calm.accent
        font.family: view.family
        font.pixelSize: 28
        font.bold: view.failed
      }
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: view.failed ? "Could not load the lyrics"
        : !view.svc || !view.svc.hasTrack ? "Nothing is playing" : "No lyrics for this song"
      textFormat: Text.PlainText
      color: view.fg
      font.family: view.family
      font.pixelSize: 16
      font.weight: Font.Bold
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: view.failed ? view.error
        : !view.svc || !view.svc.hasTrack ? "Play something to see its lyrics."
        : "YouTube Music has none for \u201C" + view.svc.title + "\u201D. Enjoy the music."
      textFormat: Text.PlainText
      color: Util.alpha(view.fg, 0.64)
      font.family: view.family
      font.pixelSize: 13
    }
  }

  // Loading: six faint bars, like lines about to appear.
  Column {
    objectName: "lyricsLoading"
    y: 40
    width: parent.width
    visible: view.busy
    spacing: 16
    Repeater {
      model: 6
      Rectangle {
        required property int index
        width: 200 + (index * 53) % 190
        height: 18
        radius: height / 2
        color: Util.alpha(view.fg, 0.08)
      }
    }
  }

  // Calm tag: says how the lyrics behave and what the keys do.
  Row {
    id: tag
    visible: !!view.lyrics && (view.timed || view.lyrics.kind === "plain")
    spacing: 8
    height: visible ? 22 : 0
    z: 3
    Rectangle {
      height: 22
      width: tagText.implicitWidth + 18
      radius: height / 2
      color: Calm.a(view.ok, 0.14)
      border.width: 1
      border.color: Calm.a(view.ok, 0.4)
      Text {
        id: tagText
        anchors.centerIn: parent
        text: view.timed ? "Synced" : "Plain text"
        textFormat: Text.PlainText
        color: view.ok
        font.family: view.family
        font.pixelSize: 11
        font.weight: Font.DemiBold
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: view.timed ? "follows the song \u00B7 j k scroll" : "j k scroll"
      textFormat: Text.PlainText
      color: Util.alpha(view.fg, 0.36)
      font.family: view.family
      font.pixelSize: 11
    }
  }

  // Synced lines: the current one sits mid-stage, big and bright; the rest
  // fade with their distance from it. No box or glow behind it.
  Item {
    id: stage
    anchors.fill: parent
    anchors.topMargin: 30
    anchors.bottomMargin: source.height
    visible: view.timed
    // A line's row is as tall as its text wraps at the current-line size, the
    // biggest: turning current moves no other line. Short lines keep lineH.
    component Probe: Text {
      readonly property real rowH: Math.max(view.lineH, implicitHeight + 16)
      visible: false
      width: lines.width - 8
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      font.family: view.family
      font.pixelSize: 22
      font.weight: Font.Bold
    }
    Probe { id: firstRow; text: view.timed && view.lyrics.lines.length ? view.lyrics.lines[0].text || " " : " " }
    Probe { id: curRow; text: " " }
    Probe { id: lastRow; text: view.timed && view.lyrics.lines.length ? view.lyrics.lines[view.lyrics.lines.length - 1].text || " " : " " }
    ListView {
      id: lines
      anchors.fill: parent
      clip: true
      model: view.timed ? view.lyrics.lines : []
      boundsBehavior: Flickable.StopAtBounds
      highlightRangeMode: ListView.ApplyRange
      // Rows differ in height: centre the current one, and let the first and
      // the last reach the middle too.
      preferredHighlightBegin: height / 2 - curRow.rowH / 2
      preferredHighlightEnd: height / 2 + curRow.rowH / 2
      highlightMoveDuration: 320
      header: Item { height: lines.height / 2 - firstRow.rowH / 2 }
      footer: Item { height: lines.height / 2 - lastRow.rowH / 2 }
      delegate: Item {
        id: ln
        required property var modelData
        required property int index
        readonly property real dist: Math.abs(index - view.line)
        width: ListView.view ? ListView.view.width : 0
        height: size.rowH
        opacity: Math.max(0.16, 1 - dist * 0.3)
        Behavior on opacity { NumberAnimation { duration: 320 } }
        Probe { id: size; text: ln.modelData.text === "" ? " " : ln.modelData.text }
        Text {
          x: 4
          width: parent.width - 8
          anchors.verticalCenter: parent.verticalCenter
          text: ln.modelData.text === "" ? " " : ln.modelData.text
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: ln.dist === 0 ? view.fg : Util.alpha(view.fg, 0.64)
          font.family: view.family
          font.pixelSize: ln.dist === 0 ? 22 : 18
          font.weight: ln.dist === 0 ? Font.Bold : Font.DemiBold
          Behavior on color { ColorAnimation { duration: 320 } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (view.svc) view.svc.seek(ln.modelData.t / 1000)
        }
      }
    }
    // The first and last lines melt into the card.
    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: 50
      gradient: Gradient {
        GradientStop { position: 0; color: Calm.surface }
        GradientStop { position: 1; color: Calm.a(Calm.surface, 0) }
      }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 50
      gradient: Gradient {
        GradientStop { position: 0; color: Calm.a(Calm.surface, 0) }
        GradientStop { position: 1; color: Calm.surface }
      }
    }
  }

  Flickable {
    id: plain
    anchors.fill: parent
    anchors.topMargin: 34
    anchors.bottomMargin: source.height + 6
    visible: !!view.lyrics && view.lyrics.kind === "plain"
    clip: true
    contentHeight: plainCol.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: plainCol
      width: plain.width
      spacing: 9
      Repeater {
        model: view.lyrics && view.lyrics.kind === "plain" ? String(view.lyrics.text).split("\n") : []
        Text {
          required property string modelData
          width: plainCol.width
          text: modelData === "" ? " " : modelData
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Util.alpha(view.fg, 0.64)
          font.family: view.family
          font.pixelSize: 15
        }
      }
    }
  }

  Text {
    id: source
    anchors.bottom: parent.bottom
    width: parent.width
    visible: text !== ""
    text: view.lyrics ? (view.lyrics.source || "") : ""
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Util.alpha(view.fg, 0.36)
    font.family: view.family
    font.pixelSize: 11
  }
}
