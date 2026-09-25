import QtQuick
import qs.Commons
import "../lib/Model.js" as Model

// Lyrics for the song that plays. Timed lines follow the music; plain
// lyrics scroll by hand.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

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

  onLineChanged: if (timed && line >= 0) lines.currentIndex = line

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    visible: !view.lyrics || view.lyrics.kind === "none"
    text: view.busy ? "Looking for lyrics" : view.error !== "" ? view.error
      : !view.svc || !view.svc.hasTrack ? "Play something to see its lyrics" : "No lyrics for this song"
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(view.fg, 0.6)
    font.family: view.family
    font.pixelSize: Style.font.body
  }

  ListView {
    id: lines
    anchors.fill: parent
    anchors.bottomMargin: source.height + Style.space(6)
    visible: view.timed
    clip: true
    model: view.timed ? view.lyrics.lines : []
    boundsBehavior: Flickable.StopAtBounds
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: height * 0.35
    preferredHighlightEnd: height * 0.45
    highlightMoveDuration: 240
    delegate: Text {
      required property var modelData
      required property int index
      width: ListView.view ? ListView.view.width : 0
      topPadding: Style.space(3)
      bottomPadding: Style.space(3)
      text: modelData.text === "" ? " " : modelData.text
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: index === view.line ? Color.accent : Util.alpha(view.fg, index < view.line ? 0.4 : 0.7)
      font.family: view.family
      font.pixelSize: index === view.line ? Style.font.title : Style.font.body
      font.bold: index === view.line
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (view.svc) view.svc.seek(parent.modelData.t / 1000)
      }
    }
  }

  Flickable {
    id: plain
    anchors.fill: parent
    anchors.bottomMargin: source.height + Style.space(6)
    visible: !!view.lyrics && view.lyrics.kind === "plain"
    clip: true
    contentHeight: plainText.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Text {
      id: plainText
      width: plain.width
      text: view.lyrics && view.lyrics.kind === "plain" ? view.lyrics.text : ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      lineHeight: 1.25
      color: Util.alpha(view.fg, 0.85)
      font.family: view.family
      font.pixelSize: Style.font.body
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
    color: Util.alpha(view.fg, 0.45)
    font.family: view.family
    font.pixelSize: Style.font.caption
  }
}
