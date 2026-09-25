import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// The top of the panel: the song, its cover, time, and every control.
Column {
  id: root

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool hasTrack: svc ? svc.hasTrack : false
  // Width kept free at the top right (the panel puts Solfa's name there).
  property real reserveRight: 0

  spacing: Style.space(10)

  Row {
    width: parent.width
    spacing: Style.space(14)

    RoundCover {
      id: cover
      width: Style.space(84)
      height: width
      source: root.svc ? root.svc.thumb : ""
      foreground: root.fg
      fill: Util.alpha(root.fg, 0.08)
      fontFamily: root.family
      dim: root.hasTrack && !root.svc.isPlaying
    }

    Column {
      width: parent.width - cover.width - actions.width - parent.spacing * 2
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.hasTrack ? root.svc.title : (root.svc && root.svc.engineLine ? root.svc.engineLine : "Nothing playing")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: root.hasTrack
      }
      Text {
        width: parent.width
        text: root.hasTrack ? (root.svc.isAd ? "Advert — your song starts after it" : root.svc.artist)
          : root.svc && root.svc.ready ? "Press / to search, or pick something below."
          : root.svc && root.svc.closed ? "Nothing plays until you turn it on." : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Util.alpha(root.fg, 0.75)
        font.family: root.family
        font.pixelSize: Style.font.body
        visible: text !== ""
      }
      Text {
        width: parent.width
        text: root.hasTrack ? root.svc.album : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Util.alpha(root.fg, 0.5)
        font.family: root.family
        font.pixelSize: Style.font.caption
        visible: text !== ""
      }
    }

    // During an advert the like button has nothing to like: Skip takes its place.
    Item {
      id: actions
      width: Math.max(skipAdButton.visible ? skipAdButton.width : likeButton.width, root.reserveRight)
      height: cover.height

      HitButton {
        id: skipAdButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasTrack && root.svc.isAd
        text: "Skip advert"
        fontFamily: root.family
        foreground: root.fg
        bordered: true
        onClicked: if (root.svc) root.svc.skipAd()
      }

      HitButton {
        id: likeButton
        minSize: Style.space(40)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasTrack && !root.svc.isAd
        iconText: root.svc && root.svc.like === "LIKE" ? Icons.heart : Icons.heartOutline
        foreground: root.svc && root.svc.like === "LIKE" ? Color.accent : root.fg
        iconSize: Style.font.iconLarge
        fontFamily: root.family
        tooltipText: root.svc && !root.svc.signedIn ? "Sign in to like songs" : (root.svc && root.svc.like === "LIKE" ? "Remove the like (f)" : "Like (f)")
        onClicked: if (root.svc) root.svc.toggleLike()
      }
    }
  }

  // ---- time
  Column {
    width: parent.width
    spacing: Style.space(2)
    visible: root.hasTrack

    PanelSlider {
      id: seek
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: root.svc && root.svc.duration > 0 ? root.svc.duration : 1
      value: root.svc ? root.svc.position : 0
      step: 1
      enabled: root.svc && root.svc.duration > 0 && !root.svc.isAd
      fillColor: Color.accent
      onReleased: function (v) { if (root.svc) root.svc.seek(v) }
    }

    Item {
      width: parent.width
      height: posText.implicitHeight
      Text {
        id: posText
        text: Model.fmtTime(seek.dragging ? seek.liveValue : (root.svc ? root.svc.position : 0))
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        text: root.svc ? Model.fmtTime(root.svc.duration) : ""
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---- controls
  // One centre line: every transport button is a 44 px square with the same
  // glyph size; play/pause is a larger square on that line. The squares are
  // the hit boxes: hover and press fill them, not just the glyph.
  Item {
    id: controls
    width: parent.width
    height: Math.max(transport.height, volumeRow.height)
    visible: root.hasTrack

    readonly property real slot: Style.space(44)
    readonly property real playSlot: Style.space(48)
    readonly property real volumeSlot: Style.space(36)
    readonly property real glyph: Style.font.iconLarge

    Row {
      id: transport
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.shuffle
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Shuffle the queue (s)"
        onClicked: if (root.svc) root.svc.shuffle()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.previous
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Previous (p)"
        onClicked: if (root.svc) root.svc.previous()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.playSlot
        iconText: root.svc && root.svc.isPlaying ? Icons.pause : Icons.play
        iconSize: Math.round(controls.glyph * 1.3)
        foreground: root.fg
        fontFamily: root.family
        bordered: true
        tooltipText: (root.svc && root.svc.isPlaying ? "Pause" : "Play") + " (space)"
        onClicked: if (root.svc) root.svc.togglePlaying()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.next
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Next (n)"
        onClicked: if (root.svc) root.svc.next()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.repeatIcon(root.svc ? root.svc.repeatMode : "NONE")
        iconSize: controls.glyph
        foreground: root.svc && root.svc.repeatMode !== "NONE" ? Color.accent : root.fg
        fontFamily: root.family
        tooltipText: Model.repeatLabel(root.svc ? root.svc.repeatMode : "NONE") + " (r)"
        onClicked: if (root.svc) root.svc.cycleRepeat()
      }
    }

    Row {
      id: volumeRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.volumeSlot
        iconText: Icons.volumeIcon(root.svc ? root.svc.volume : 100, root.svc ? root.svc.muted : false)
        foreground: root.fg
        fontFamily: root.family
        tooltipText: root.svc && root.svc.muted ? "Unmute (m)" : "Mute (m)"
        onClicked: if (root.svc) root.svc.toggleMute()
      }
      // On a narrow card the slider gives way before it runs into the
      // transport buttons; m and the volume keys still work.
      PanelSlider {
        anchors.verticalCenter: parent.verticalCenter
        visible: controls.width >= transport.width + controls.volumeSlot + width + Style.space(24)
        width: Style.space(110)
        bar: root.bar
        minimum: 0
        maximum: 100
        step: 1
        integer: true
        value: root.svc ? (root.svc.muted ? 0 : root.svc.volume) : 100
        onMoved: function (v) { if (root.svc) root.svc.setVolume(v) }
        onReleased: function (v) { if (root.svc) root.svc.setVolume(v) }
      }
    }
  }
}
