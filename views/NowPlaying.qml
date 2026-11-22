import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons
import "../lib/Calm.js" as Calm
import "../lib/Motion.js" as Motion

// The top of the panel: the song, its cover, time, and every control.
Column {
  id: root

  property var svc: null
  property QtObject bar: null
  readonly property color fg: Calm.fg
  readonly property string family: Calm.font
  readonly property bool hasTrack: svc ? svc.hasTrack : false
  // Width kept free at the top right (the panel puts Solfa's name there).
  property real reserveRight: 0
  // Room for the header row (name, buttons) the panel draws over the top.
  property real topInset: 0
  // Decoration moves only while the panel is open and a song plays.
  // The panel's open clock, 0 to 350 ms (settled; also reduce-motion).
  property real openMs: 350
  function eff(delay, dur) { return Motion.effects(openMs, delay, dur) }
  readonly property bool live: !!(svc && svc.panelOpen && svc.hasTrack && svc.isPlaying)

  spacing: Style.space(20)
  topPadding: topInset + (topInset > 0 ? Style.space(24) : 0)

  // The save-to-playlist button was pressed (the panel opens the picker).
  signal saveRequested()
  // The Radio chip was pressed (the panel starts it and says "Radio from <title>", as key R does).
  signal radioRequested()

  Row {
    width: parent.width
    spacing: Style.space(14)

    RoundCover {
      id: cover
      width: Style.space(104)
      height: width
      cornerRadius: Style.space(22)
      source: root.svc ? root.svc.thumb : ""
      foreground: root.fg
      fill: Util.alpha(root.fg, 0.08)
      fontFamily: root.family
      motif: true
      dim: root.hasTrack && !root.svc.isPlaying
      breathe: root.hasTrack
      live: root.live
      reduceMotion: Style.reduceMotion
      // pops .8 to 1 and fades in (no turn), 20 ms in
      scale: 0.8 + 0.2 * Motion.spatial(root.openMs, 20, 200)
      opacity: root.eff(20, 160)
    }

    Column {
      width: parent.width - cover.width - actions.width - parent.spacing * 2
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(3)
      // title and artist slide in from the left, 100 ms in
      opacity: root.eff(40, 200)
      transform: Translate { x: -Style.space(12) * (1 - root.eff(40, 200)) }

      // A new title writes itself (30 ms a letter) only while the panel is
      // open and a song plays, and never under reduce-motion. The invisible
      // copy holds the full height, so nothing below jumps.
      Item {
        id: titleBox
        width: parent.width
        height: titleGhost.implicitHeight
        readonly property string full: root.hasTrack ? root.svc.title : (root.svc && root.svc.engineLine ? root.svc.engineLine : "Nothing playing")
        readonly property bool typing: root.live && !Style.reduceMotion && root.hasTrack
        property real shown: full.length
        onFullChanged: {
          typeAnim.stop()
          if (!typing || full.length === 0) { shown = full.length; return }
          shown = 0
          typeAnim.duration = full.length * Motion.typeMs
          typeAnim.from = 0; typeAnim.to = full.length; typeAnim.start()
        }
        onTypingChanged: if (!typing) { typeAnim.stop(); shown = full.length }
        NumberAnimation { id: typeAnim; target: titleBox; property: "shown"; easing.type: Easing.Linear }
        Text {
          id: titleGhost
          width: parent.width
          text: titleBox.full
          opacity: 0
          textFormat: Text.PlainText
          maximumLineCount: 2
          wrapMode: Text.WordWrap
          font.family: root.family
          font.pixelSize: Style.space(21)
          font.bold: root.hasTrack
        }
        Text {
          width: parent.width
          text: titleBox.full.substring(0, Math.floor(titleBox.shown))
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WordWrap
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.space(21)
          font.bold: root.hasTrack
        }
      }
      Text {
        width: parent.width
        text: root.hasTrack ? (root.svc.isAd ? (root.svc.adDuration > 0 ? "Advert — your song starts in " + Model.fmtTime(root.svc.adLeft) : "Advert — your song starts after it") : root.svc.artist)
          : root.svc && root.svc.ready ? "Press / to search, or pick something below."
          : root.svc && root.svc.closed ? "Nothing plays until you turn it on." : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Util.alpha(root.fg, 0.75)
        font.family: root.family
        font.pixelSize: Style.space(13)
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

    // During an advert the like button has nothing to like: it hides, and
    // Skip sits by the advert's clock below.
    Item {
      id: actions
      width: Math.max(likeButton.width, root.reserveRight)
      height: cover.height

      EventGlow { id: likeGlow; objectName: "likeGlow"; anchors.centerIn: likeButton; size: Style.space(150) }
      Connections {
        target: root.svc
        function onLikeChanged() { if (root.svc.like === "LIKE" && root.live) likeGlow.fire("like") }
      }
      HitButton {
        id: likeButton
        onPressedDown: function (it) { cover.lookAt(it) }
        minSize: Style.space(36)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasTrack && !root.svc.isAd
        iconText: ""
        VIcon { anchors.centerIn: parent; name: "heart"; size: Style.space(20); filled: !!(root.svc && root.svc.like === "LIKE"); color: root.svc && root.svc.like === "LIKE" ? Calm.accent : root.fg; stroke: 1.7 }
        foreground: root.svc && root.svc.like === "LIKE" ? Calm.accent : root.fg
        // a round chip behind the heart, tinted once it is liked
        Rectangle {
          z: -1
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height); height: width
          radius: width / 2
          color: root.svc && root.svc.like === "LIKE" ? Util.alpha(Calm.accent, 0.22) : Util.alpha(root.fg, 0.07)
        }
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
    // The bar's line sits mid-way in its slider box: cover to line 28, line to times 8.
    topPadding: Style.space(28) - Style.space(20) - seek.height / 2
    spacing: Style.space(8) - seek.height / 2
    visible: root.hasTrack

    PanelSlider {
      id: seek
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: root.svc && root.svc.isAd ? Math.max(1, root.svc.adDuration) : (root.svc && root.svc.duration > 0 ? root.svc.duration : 1)
      // the fill grows from 0 to the real position, 140 ms in
      value: (root.svc ? (root.svc.isAd ? root.svc.adPosition : root.svc.position) : 0) * root.eff(60, 220)
      step: 1
      enabled: root.svc && root.svc.duration > 0 && !root.svc.isAd
      fillColor: root.svc && root.svc.isAd ? Color.urgent : Calm.accent
      onReleased: function (v) { if (root.svc) root.svc.seek(v) }
    }

    Item {
      width: parent.width
      height: Math.max(posText.implicitHeight, adBadge.visible ? adBadge.height : 0, skipAd.visible ? skipAd.height : 0)
      Text {
        id: posText
        anchors.verticalCenter: parent.verticalCenter
        text: root.svc && root.svc.isAd ? Model.fmtTime(root.svc.adPosition)
          : Model.fmtTime(seek.dragging ? seek.liveValue : (root.svc ? root.svc.position : 0))
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      // What is playing is an advert, not the song: said in the middle, in
      // the warning colour, with the time it has left.
      Rectangle {
        id: adBadge
        anchors.centerIn: parent
        visible: !!(root.svc && root.svc.isAd)
        width: adBadgeText.implicitWidth + Style.space(20)
        height: adBadgeText.implicitHeight + Style.space(8)
        radius: height / 2
        color: Util.alpha(Color.urgent, 0.18)
        border.color: Color.urgent
        border.width: 1
        Text {
          id: adBadgeText
          anchors.centerIn: parent
          text: "THIS IS AN AD" + (root.svc && root.svc.adDuration > 0 ? " · " + Model.fmtTime(root.svc.adLeft) + " left" : "")
          textFormat: Text.PlainText
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      // Skip: filled in the accent colour with the usual skip arrow, the
      // one thing to press during an advert. YouTube decides when an
      // advert can be skipped; before then this shows the wait instead of
      // a button that presses into nothing.
      Rectangle {
        id: skipAd
        readonly property bool skippable: !!(root.svc && root.svc.adSkippable)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !!(root.svc && root.svc.isAd)
        width: skipRow.implicitWidth + Style.space(24)
        height: skipRow.implicitHeight + Style.space(12)
        radius: height / 2
        color: !skippable ? Util.alpha(root.fg, 0.12)
          : skipMouse.pressed ? Qt.darker(Calm.accent, 1.25) : skipMouse.containsMouse ? Qt.lighter(Calm.accent, 1.15) : Calm.accent
        scale: skippable && skipMouse.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        readonly property color ink: !skippable ? Util.alpha(root.fg, 0.6)
          : (0.299 * Calm.accent.r + 0.587 * Calm.accent.g + 0.114 * Calm.accent.b) > 0.6 ? "#101010" : "#ffffff"
        Row {
          id: skipRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: skipAd.skippable ? "Skip ad" : "Can't skip yet"
            textFormat: Text.PlainText
            color: skipAd.ink
            font.family: root.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: skipAd.skippable
            text: Icons.next
            textFormat: Text.PlainText
            color: skipAd.ink
            font.family: root.family
            font.pixelSize: Style.font.iconLarge
          }
        }
        MouseArea {
          id: skipMouse
          anchors.fill: parent
          enabled: skipAd.skippable
          hoverEnabled: true
          cursorShape: skipAd.skippable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (root.svc) root.svc.skipAd()
        }
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !(root.svc && root.svc.isAd)
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
    height: transport.height + Style.space(20) + volumeRow.height
    visible: root.hasTrack

    readonly property real slot: Style.space(48)
    readonly property real playSlot: Style.space(62)
    readonly property real volumeSlot: Style.space(36)
    readonly property real glyph: Style.space(20)

    Row {
      id: transport
      spacing: Style.space(10)
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter

      HitButton {
        opacity: root.eff(70, 180)
        transform: Translate { y: Style.space(10) * (1 - root.eff(70, 180)) }
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: "shuffle"; size: Style.space(22); color: root.fg; stroke: 1.7 }
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Shuffle the queue (s)"
        onClicked: if (root.svc) root.svc.shuffle()
      }
      HitButton {
        opacity: root.eff(85, 180)
        transform: Translate { y: Style.space(10) * (1 - root.eff(85, 180)) }
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: "prev"; size: Style.space(22); filled: true; color: root.fg }
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Previous (p)"
        onClicked: if (root.svc) root.svc.previous()
      }
      HitButton {
        // the play disc comes last, with a soft scale overshoot
        opacity: root.eff(145, 200)
        transform: [
          Translate { y: Style.space(10) * (1 - root.eff(145, 200)) },
          Scale { origin.x: width / 2; origin.y: height / 2; xScale: 0.7 + 0.3 * Motion.spatial(root.openMs, 145, 200); yScale: xScale }
        ]
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.playSlot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: root.svc && root.svc.isPlaying ? "pause" : "play"; size: Style.space(26); filled: true; color: parent.playInk }
        // The one filled control: a calm accent disc with a dark glyph.
        foreground: playInk
        readonly property color playInk: (0.299 * Calm.accent.r + 0.587 * Calm.accent.g + 0.114 * Calm.accent.b) > 0.6 ? "#101010" : "#ffffff"
        fontFamily: root.family
        tooltipText: (root.svc && root.svc.isPlaying ? "Pause" : "Play") + " (space)"
        Rectangle {
          z: -1
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height); height: width
          radius: width / 2
          color: Calm.accent
          opacity: parent.hovered ? 0.92 : 1
        }
        onClicked: if (root.svc) root.svc.togglePlaying()
      }
      HitButton {
        opacity: root.eff(100, 180)
        transform: Translate { y: Style.space(10) * (1 - root.eff(100, 180)) }
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: "next"; size: Style.space(22); filled: true; color: root.fg }
        foreground: root.fg
        fontFamily: root.family
        tooltipText: "Next (n)"
        onClicked: if (root.svc) root.svc.next()
      }
      HitButton {
        opacity: root.eff(115, 180)
        transform: Translate { y: Style.space(10) * (1 - root.eff(115, 180)) }
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: root.svc && root.svc.repeatMode === "ONE" ? "repeatOnce" : "repeat"; size: Style.space(22); color: root.svc && root.svc.repeatMode !== "NONE" ? Calm.accent : root.fg; stroke: 1.7 }
        foreground: root.svc && root.svc.repeatMode !== "NONE" ? Calm.accent : root.fg
        fontFamily: root.family
        tooltipText: Model.repeatLabel(root.svc ? root.svc.repeatMode : "NONE") + " (r)"
        Rectangle {
          z: -1
          anchors.centerIn: parent
          width: Style.space(48); height: width
          radius: width / 2
          color: Util.alpha(Calm.accent, 0.22)
          visible: !!(root.svc && root.svc.repeatMode !== "NONE")
        }

        onClicked: if (root.svc) root.svc.cycleRepeat()
      }
      HitButton {
        opacity: root.eff(130, 180)
        transform: Translate { y: Style.space(10) * (1 - root.eff(130, 180)) }
        objectName: "saveButton"
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        visible: !!(root.svc && !root.svc.isAd)
        iconText: ""
        VIcon { anchors.centerIn: parent; name: "queue"; size: Style.space(22); color: root.fg; stroke: 1.7 }
        foreground: root.fg
        fontFamily: root.family
        tooltipText: root.svc && !root.svc.signedIn ? "Sign in to save to a playlist" : "Save to a playlist (S)"
        onClicked: root.saveRequested()
      }
    }

    // volume, its number, Sleep and Radio: one line under the transport
    Row {
      id: volumeRow
      // volume and chips fade and slide up, 220 ms in
      opacity: root.eff(100, 200)
      transform: Translate { y: Style.space(8) * (1 - root.eff(100, 200)) }
      // Labels give way before the slider does: below this slider width the
      // Sleep and Radio chips show only their icons.
      readonly property real fullChips: 2 * (Style.space(24) + Style.space(20) + Style.space(6)) + sleepMetrics.advanceWidth + radioMetrics.advanceWidth
      readonly property bool tight: width - controls.volumeSlot - volText.width - spacing * 4 - fullChips < Style.space(72)
      TextMetrics { id: sleepMetrics; font.family: root.family; font.pixelSize: Style.space(16); font.weight: Font.DemiBold
        text: root.svc && root.svc.sleepMode !== "off" ? Model.sleepLabel(root.svc.sleepMode) : "Sleep" }
      TextMetrics { id: radioMetrics; font.family: root.family; font.pixelSize: Style.space(16); font.weight: Font.DemiBold; text: "Radio" }
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(8)

      HitButton {
        onPressedDown: function (it) { cover.lookAt(it) }
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.volumeSlot
        iconText: ""
        VIcon { anchors.centerIn: parent; name: root.svc && (root.svc.muted || root.svc.volume === 0) ? "mute" : "volume"; size: Style.space(22); color: Util.alpha(root.fg, 0.75); stroke: 1.7 }
        foreground: root.fg
        fontFamily: root.family
        tooltipText: root.svc && root.svc.muted ? "Unmute (m)" : "Mute (m)"
        onClicked: if (root.svc) root.svc.toggleMute()
      }
      PanelSlider {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(48), parent.width - controls.volumeSlot - volText.width - sleepChip.width - radioChip.width - parent.spacing * 4)
        bar: root.bar
        minimum: 0
        maximum: 100
        step: 1
        integer: true
        fillColor: Calm.accent
        value: root.svc ? (root.svc.muted ? 0 : root.svc.volume) : 100
        onMoved: function (v) { if (root.svc) root.svc.setVolume(v) }
        onReleased: function (v) { if (root.svc) root.svc.setVolume(v) }
      }
      Text {
        id: volText
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        text: (root.svc ? (root.svc.muted ? 0 : root.svc.volume) : 100) + "%"
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        id: sleepChip
        anchors.verticalCenter: parent.verticalCenter
        width: sleepRow.implicitWidth + Style.space(24); height: Style.space(40); radius: height / 2
        color: sleepMouse.containsMouse ? Calm.a(Calm.fg, 0.1) : Calm.wash
        border.width: 1; border.color: Calm.hair
        Row {
          id: sleepRow
          anchors.centerIn: parent
          spacing: volumeRow.tight ? 0 : Style.space(6)
          VIcon { anchors.verticalCenter: parent.verticalCenter; name: "moon"; size: Style.space(20); color: root.fg; stroke: 1.8 }
          Text { visible: !volumeRow.tight; anchors.verticalCenter: parent.verticalCenter; text: root.svc && root.svc.sleepMode !== "off" ? Model.sleepLabel(root.svc.sleepMode) : "Sleep"; textFormat: Text.PlainText; color: root.fg; font.family: root.family; font.pixelSize: Style.space(16); font.weight: Font.DemiBold }
        }
        MouseArea {
          id: sleepMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.svc) {
            var o = Model.SLEEP_OPTIONS, k = o.indexOf(root.svc.sleepMode)
            root.svc.setSleepMode(o[(k + 1) % o.length])
          }
        }
      }
      Rectangle {
        id: radioChip
        anchors.verticalCenter: parent.verticalCenter
        width: radioRow.implicitWidth + Style.space(24); height: Style.space(40); radius: height / 2
        color: radioMouse.containsMouse ? Calm.a(Calm.fg, 0.1) : Calm.wash
        border.width: 1; border.color: Calm.hair
        Row {
          id: radioRow
          anchors.centerIn: parent
          spacing: volumeRow.tight ? 0 : Style.space(6)
          VIcon { anchors.verticalCenter: parent.verticalCenter; name: "radio"; size: Style.space(20); color: root.fg; stroke: 1.8 }
          Text { visible: !volumeRow.tight; anchors.verticalCenter: parent.verticalCenter; text: "Radio"; textFormat: Text.PlainText; color: root.fg; font.family: root.family; font.pixelSize: Style.space(16); font.weight: Font.DemiBold }
        }
        MouseArea {
          id: radioMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.svc && root.svc.hasTrack) root.radioRequested()
        }
      }
    }
  }
}
