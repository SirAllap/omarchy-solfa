import QtQuick
import QtQuick.Effects
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
  readonly property bool awake: coverMouse.containsMouse || playMouse.containsMouse
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
          shadowColor: card.awake ? Calm.a(Calm.accent, 0.4) : Qt.rgba(0, 0, 0, 0.55)
          shadowBlur: 1
          shadowVerticalOffset: card.awake ? 12 : 16
          shadowOpacity: 1
          Behavior on shadowColor { ColorAnimation { duration: 180 } }
        }
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

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 200
      height: 44
      Rectangle {
        id: playOnButton
        objectName: "offPlayOn"
        anchors.fill: parent
        radius: height / 2
        color: playMouse.pressed ? Calm.a(Calm.accent, 0.8) : Calm.accent
        Accessible.role: Accessible.Button
        Accessible.name: "Play on"
        Accessible.onPressAction: card.playOn()
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Calm.a(Calm.accent, 0.55)
          shadowBlur: card.awake ? 1 : 0.55
          shadowVerticalOffset: card.awake ? 10 : 5
          shadowOpacity: 1
          Behavior on shadowBlur { NumberAnimation { duration: 180 } }
        }
        Text {
          anchors.centerIn: parent
          text: Icons.play + " Play on"
          textFormat: Text.PlainText
          color: Calm.onAccent
          font.family: card.family
          font.pixelSize: 15
          font.bold: true
        }
      }
      MouseArea {
        id: playMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.playOn()
      }
    }

    Text {
      objectName: "offNote"
      width: parent.width
      text: card.hasPos ? "Starts YouTube Music in the background and picks up at " + card.fmt(card.pos) + "."
        : "Starts YouTube Music in the background and picks " + (card.svc ? card.svc.lastTitle : "") + " up where you left it."
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

  // The round power circle IS the Turn on button: click, Enter (the panel's key
  // handler) or Space turns Solfa on. Hover and press change the fill; Tab shows a ring.
  Rectangle {
    id: power
    visible: !card.hasLast
    objectName: "offPower"
    anchors.horizontalCenter: parent.horizontalCenter
    width: 70
    height: width
    radius: width / 2
    activeFocusOnTab: true
    color: powerMouse.pressed ? Calm.a(Calm.accent, 0.32) : powerMouse.containsMouse ? Calm.a(Calm.accent, 0.18) : Calm.wash
    border.width: 1
    border.color: Calm.a(Calm.accent, powerMouse.containsMouse || power.activeFocus ? 0.9 : 0.5)
    scale: powerMouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }
    Accessible.role: Accessible.Button
    Accessible.name: "Turn Solfa on"
    Accessible.onPressAction: power.turnOn()
    function turnOn() { if (card.svc) card.svc.startEngine() }
    Keys.onReturnPressed: turnOn()
    Keys.onEnterPressed: turnOn()
    Keys.onSpacePressed: turnOn()
    // Keyboard focus ring, outside the circle.
    Rectangle {
      objectName: "offPowerFocus"
      anchors.centerIn: parent
      width: parent.width + 8
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: Calm.accent
      visible: power.activeFocus
    }
    Text {
      anchors.centerIn: parent
      text: Icons.power
      textFormat: Text.PlainText
      color: Calm.accent
      font.family: card.family
      font.pixelSize: 28
    }
    MouseArea {
      id: powerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { power.forceActiveFocus(); power.turnOn() }
    }
  }

  Text {
    visible: !card.hasLast
    width: parent.width
    text: "Turn Solfa on"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: card.fg
    font.family: card.family
    font.pixelSize: 18
    font.bold: true
  }

  Text {
    visible: !card.hasLast
    width: parent.width
    text: "It starts YouTube Music in the background. Nothing plays until you do."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Calm.muted
    font.family: card.family
    font.pixelSize: 13
  }

  KeyHint {
    visible: !card.hasLast
    anchors.horizontalCenter: parent.horizontalCenter
    keys: "↵"
    label: "or press Enter"
    bar: card.bar
  }
}
