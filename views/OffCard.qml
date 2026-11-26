import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../lib"
import qs.Ui
import qs.Commons
import "../lib/Icons.js" as Icons

// Solfa is off (the engine closed on purpose, or after it kept crashing):
// nothing below would work, so under the header ("Solfa is off") the panel
// shows only the way back on.
Column {
  id: card

  property var svc: null
  property QtObject bar: null
  readonly property color fg: Calm.fg
  readonly property string family: Calm.font

  spacing: 12

  readonly property bool hasLast: !!svc && !!svc.lastTitle
  readonly property real pos: svc && svc.lastPosition !== undefined ? Number(svc.lastPosition) : -1
  readonly property real len: svc && svc.lastDuration !== undefined ? Number(svc.lastDuration) : 0
  // Where it was left is known: the thin line and "picks up at m:ss".
  readonly property bool hasPos: len > 0 && pos >= 0
  readonly property string sub: !svc ? "" : (svc.lastArtist || "") + (svc.lastArtist && svc.lastAlbum ? " · " : "") + (svc.lastAlbum || "")
  function playOn() { if (card.svc) card.svc.startAndPlay() }
  // Pointer on the cover or the button: the cover gets its colour back, lifts, and shows a round play.
  readonly property bool awake: coverMouse.containsMouse
  function fmt(s) { var n = Math.max(0, Math.floor(s)); return Math.floor(n / 60) + ":" + (n % 60 < 10 ? "0" : "") + (n % 60) }

  // A last song is known: a preview of what plays, and one button that plays it.
  Column {
    id: lastSong
    objectName: "offLast"
    visible: card.hasLast
    width: parent.width
    spacing: 12

    Text {
      objectName: "offEyebrow"
      width: parent.width
      text: "LAST PLAYED"
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: Calm.muted
      font.family: card.family
      font.pixelSize: 11
      font.letterSpacing: 1.6
    }

    Item {
      id: coverBox
      anchors.horizontalCenter: parent.horizontalCenter
      width: 168
      height: width

      // The cover's colour, spread softly behind the whole card: grey at rest, in colour on hover.
      CoverGlow {
        objectName: "offGlow"
        z: -1
        anchors.centerIn: parent
        width: 440
        height: 380
        source: card.svc ? card.svc.lastThumb : ""
        active: card.awake
        opacity: card.awake ? 0.4 : 0.14
        Behavior on opacity { NumberAnimation { duration: 400 } }
      }

      // The hover shadow in the cover's own colour: a tight blurred copy of it, a little below.
      CoverGlow {
        objectName: "offCoverShadow"
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 14
        width: 340
        height: 340
        source: card.svc ? card.svc.lastThumb : ""
        active: true
        opacity: card.awake ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
      }

      Item {
        id: lift
        anchors.fill: parent
        scale: card.awake ? 1 : 0.97
        y: card.awake ? -2 : 0
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, card.awake ? 0.35 : 0.55)
          shadowBlur: 1
          shadowVerticalOffset: card.awake ? 12 : 16
          shadowOpacity: 1        }
        RoundCover {
          id: lastCover
          objectName: "offCover"
          anchors.fill: parent
          source: card.svc ? card.svc.lastThumb : ""
          foreground: card.fg
          fontFamily: card.family
          cornerRadius: 16
          asleep: !card.awake
        }
        Rectangle {
          objectName: "offCoverPlay"
          anchors.centerIn: parent
          width: 58
          height: width
          radius: width / 2
          color: Qt.rgba(1, 1, 1, 0.92)
          opacity: card.awake ? 1 : 0
          scale: card.awake ? 1 : 0.85
          Behavior on opacity { NumberAnimation { duration: 140 } }
          Behavior on scale { NumberAnimation { duration: 140 } }
          Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 2
            text: Icons.play
            textFormat: Text.PlainText
            color: Qt.rgba(0.05, 0.055, 0.07, 1)
            font.family: card.family
            font.pixelSize: 28
          }
        }
      }
      MouseArea {
        id: coverMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.playOn()
      }
    }

    Column {
      width: parent.width
      spacing: 4
      Text {
        objectName: "offLastTitle"
        width: parent.width
        text: card.svc ? card.svc.lastTitle : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: card.fg
        font.family: card.family
        font.pixelSize: 20
        font.bold: true
      }
      Text {
        objectName: "offLastArtist"
        width: parent.width
        visible: text !== ""
        text: card.sub
        textFormat: Text.PlainText
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: Calm.muted
        font.family: card.family
        font.pixelSize: 13
      }
    }

    // Where it was left, read only: 1:42 ──●── 3:58.
    Row {
      id: progress
      objectName: "offProgress"
      visible: card.hasPos
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      readonly property real frac: card.hasPos ? Math.max(0, Math.min(1, card.pos / card.len)) : 0
      readonly property color ink: card.awake ? Calm.accent : Calm.a(Calm.fg, 0.35)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: card.fmt(card.pos)
        textFormat: Text.PlainText
        color: Calm.muted
        font.family: card.family
        font.pixelSize: 12
      }
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 200
        height: 10
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; radius: 1; color: Calm.hair }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * progress.frac; height: 2; radius: 1; color: progress.ink }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: parent.width * progress.frac - width / 2; width: 8; height: 8; radius: 4; color: progress.ink }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: card.fmt(card.len)
        textFormat: Text.PlainText
        color: Calm.muted
        font.family: card.family
        font.pixelSize: 12
      }
    }

    Text {
      objectName: "offNote"
      width: parent.width
      text: card.hasPos ? "Click the cover to play on. It starts YouTube Music in the background and picks up at " + card.fmt(card.pos) + "."
        : "Click the cover to play on. It starts YouTube Music in the background and picks " + (card.svc ? card.svc.lastTitle : "") + " up where you left it."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      color: Calm.muted
      font.family: card.family
      font.pixelSize: 13
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      KeyHint { keys: "↵"; label: "Play on"; bar: card.bar }
      KeyHint { keys: "Esc"; label: "Close"; bar: card.bar }
    }
  }

  // Never played on this computer (a fresh install): a welcome. The record is the way on; the
  // chips turn Solfa on and open what they name; "Sign in" turns it on and opens Google's sign-in.
  signal tabRequested(string key)
  function start(key) {
    if (!card.svc) return
    card.svc.startEngine()
    card.tabRequested(key || "search")
  }
  function signIn() { if (card.svc) { card.svc.signInWhenUp = true; card.svc.startEngine() } }

  Column {
    id: firstRun
    objectName: "offFirstRun"
    visible: !card.hasLast
    width: parent.width
    spacing: 0

    Text {
      width: parent.width
      text: "WELCOME"
      horizontalAlignment: Text.AlignHCenter
      color: Calm.muted
      font.family: card.family
      font.pixelSize: 11
      font.letterSpacing: 1.8
    }
    Item { width: 1; height: 12 }

    Item {
      id: deck
      objectName: "offRecord"
      anchors.horizontalCenter: parent.horizontalCenter
      width: 186
      height: 186
      readonly property bool hot: recordMouse.containsMouse
      property real speed: hot ? 0.24 : 0.035   // degrees per ms
      Behavior on speed { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      Accessible.role: Accessible.Button
      Accessible.name: "Start Solfa"
      Accessible.onPressAction: card.start("search")

      // A soft accent halo that brightens on hover.
      Rectangle {
        id: haloSrc
        anchors.centerIn: parent
        width: 176; height: 176; radius: 88
        color: Calm.accent
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: haloSrc
        anchors.margins: -30
        source: haloSrc
        blurEnabled: true
        blur: 1
        blurMax: 40
        autoPaddingEnabled: true
        opacity: deck.hot ? 0.6 : 0.28
        Behavior on opacity { NumberAnimation { duration: 300 } }
      }

      // The record turns; its sheen stays still, as light on a real one does.
      Item {
        id: disc
        anchors.centerIn: parent
        width: 170; height: 170
        FrameAnimation {
          running: card.visible && firstRun.visible && !Style.reduceMotion
          onTriggered: disc.rotation = (disc.rotation + frameTime * 1000 * deck.speed) % 360
        }
        Rectangle { anchors.fill: parent; radius: width / 2; color: "#14151d"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.07) }
        Repeater {
          model: 16
          Rectangle {
            required property int index
            anchors.centerIn: parent
            width: 160 - index * 6; height: width; radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, index % 3 === 0 ? 0.06 : 0.03)
          }
        }
        Rectangle {
          anchors.centerIn: parent
          width: 62; height: 62; radius: 31
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Calm.accent }
            GradientStop { position: 1; color: Qt.rgba(0.73, 0.6, 0.97, 1) }
          }
          // A small mark so the turn reads.
          Rectangle { x: 40; y: 14; width: 6; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.55) }
        }
        Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: "#0c0d14" }
      }
      Shape {
        anchors.fill: disc
        anchors.centerIn: parent
        x: disc.x; y: disc.y
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          fillGradient: ConicalGradient {
            centerX: 85; centerY: 85; angle: 40
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.08; color: Qt.rgba(1, 1, 1, 0.09) }
            GradientStop { position: 0.16; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.58; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 0.66; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
          }
          PathAngleArc { centerX: 85; centerY: 85; radiusX: 85; radiusY: 85; startAngle: 0; sweepAngle: 360 }
        }
      }
      // Hover: a round play disc on the label.
      Rectangle {
        anchors.centerIn: parent
        width: 56; height: 56; radius: 28
        color: Qt.rgba(0.94, 0.95, 1, 0.95)
        opacity: deck.hot ? 1 : 0
        scale: deck.hot ? 1 : 0.85
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: Icons.play; color: "#0f1020"; font.family: card.family; font.pixelSize: 22 }
      }
      MouseArea {
        id: recordMouse
        anchors.fill: disc
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.start("search")
      }
    }
    Item { width: 1; height: 16 }

    Text {
      width: parent.width
      text: "Put a record on"
      horizontalAlignment: Text.AlignHCenter
      color: card.fg
      font.family: card.family
      font.pixelSize: 21
      font.bold: true
    }
    Item { width: 1; height: 3 }
    Text {
      width: parent.width
      text: "YouTube Music, right in your bar."
      horizontalAlignment: Text.AlignHCenter
      color: Calm.muted
      font.family: card.family
      font.pixelSize: 13
    }
    Item { width: 1; height: 14 }

    // Each chip does what it says: Solfa turns on and that tab opens.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 8
      Repeater {
        model: [{ key: "search", label: "Search", icon: Icons.search }, { key: "library", label: "Your library", icon: Icons.tabLibrary }, { key: "lyrics", label: "Synced lyrics", icon: Icons.tabLyrics }]
        Rectangle {
          id: chip
          required property var modelData
          objectName: "offChip_" + modelData.key
          width: chipRow.implicitWidth + 20
          height: 28
          radius: 14
          color: chipMouse.pressed ? Calm.a(Calm.accent, 0.28) : chipMouse.containsMouse ? Calm.a(Calm.accent, 0.16) : Calm.a(card.fg, 0.05)
          border.width: 1
          border.color: chipMouse.containsMouse ? Calm.a(Calm.accent, 0.6) : Calm.a(card.fg, 0.08)
          scale: chipMouse.pressed ? 0.96 : 1
          Behavior on color { ColorAnimation { duration: 140 } }
          Behavior on scale { NumberAnimation { duration: 110 } }
          Accessible.role: Accessible.Button
          Accessible.name: modelData.label
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: chip.modelData.icon; color: chipMouse.containsMouse ? Calm.accent : Calm.muted; font.family: card.family; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Text { text: chip.modelData.label; color: card.fg; opacity: 0.85; font.family: card.family; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.start(chip.modelData.key) }
        }
      }
    }
    Item { width: 1; height: 14 }

    Text {
      width: parent.width
      text: "Click the record to start. YouTube Music opens in the background, and you pick the first song."
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      color: Calm.muted
      font.family: card.family
      font.pixelSize: 12
    }

    // Not signed in yet: the way to your own library, in one click.
    Item { width: 1; height: 10; visible: signLine.visible }
    Row {
      id: signLine
      objectName: "offSignIn"
      visible: !!card.svc && !card.svc.signedIn
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 5
      Text { text: "Have a YouTube Music account?"; color: Calm.muted; font.family: card.family; font.pixelSize: 12 }
      Text {
        text: "Sign in"
        color: Calm.accent
        font.family: card.family
        font.pixelSize: 12
        font.bold: true
        font.underline: signMouse.containsMouse
        MouseArea { id: signMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.signIn() }
      }
    }
    Item { width: 1; height: 12 }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      KeyHint { keys: "↵"; label: "Start"; bar: card.bar }
      KeyHint { keys: "Esc"; label: "Close"; bar: card.bar }
    }
  }
}
