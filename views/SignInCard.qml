import QtQuick
import qs.Ui
import qs.Commons

// Signing in (in a plain Google window of its own, which Google accepts),
// and the way out of any page that is not YouTube Music (Google's cookie
// page, a Google page, or a page that failed to load).
Column {
  id: card

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  // gated: the engine sits on a page other than YouTube Music.
  readonly property bool waiting: svc ? svc.gated : false
  readonly property bool shown: svc && svc.engine ? !!svc.engine.shown : false
  readonly property bool signingIn: svc ? svc.signingIn : false
  // The window reached the app and is hidden: Google's cookie is being saved.
  readonly property bool saving: signingIn && svc && svc.engine ? !!svc.engine.signinSaving : false
  readonly property string host: svc && svc.account ? (svc.account.host || "") : ""
  readonly property bool cookies: host === "consent.youtube.com"
  readonly property bool google: /(^|\.)google\.[a-z.]+$/.test(host) || host === "www.youtube.com"
  readonly property bool broken: waiting && !signingIn && !cookies && !google
  // The last sign-in window closed without the account in.
  readonly property bool failed: svc ? !!svc.signinError && !signingIn : false

  spacing: Style.space(10)

  Text {
    width: parent.width
    text: card.saving ? "Saving your sign-in"
      : card.signingIn ? "Sign in in the Google window"
      : !card.waiting ? (card.failed ? "Signing in did not finish" : "Sign in to YouTube Music")
      : card.broken ? "YouTube Music did not load"
      : card.shown ? "Finish in the YouTube Music window"
      : card.cookies ? "YouTube Music needs you once"
      : "Signing in was not finished"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: card.fg
    font.family: card.family
    font.pixelSize: Style.font.title
    font.bold: true
  }

  Text {
    width: parent.width
    text: card.saving
      ? "Almost done. Solfa closes the window by itself in under a minute, then YouTube Music plays again."
      : card.signingIn
      ? "YouTube Music waits while it is open. Solfa closes the window soon after you are in, and plays again; closing it yourself also works."
      : !card.waiting && card.failed
      ? "YouTube Music is still signed out. Try again: Google asks which account this time."
      : !card.waiting
      ? "Your playlists, liked songs and likes need your Google account. A Google window opens once; Solfa closes it when you are signed in."
      : card.broken ? "Check the connection, then try again."
      : card.shown ? "Answer Google's cookie question, then hide the window."
      : card.cookies ? "In the EU, Google asks every new browser whether YouTube may use cookies for tracking and personalised ads. Solfa is a new browser to Google, so it asks once. Your answer is sent to Google and kept. Music plays either way."
      : "Sign in, or go back to YouTube Music without signing in."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(card.fg, 0.7)
    font.family: card.family
    font.pixelSize: Style.font.body
  }

  // Google's cookie question: the answer is the main thing here, its two
  // choices side by side and alike (neither one is pushed). Signing in or
  // answering in the window are other ways, set apart below.
  readonly property bool asking: waiting && cookies && !shown

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(8)

    Button {
      visible: !card.shown && !card.broken && !card.signingIn && !card.asking
      text: "Sign in"
      fontFamily: card.family
      foreground: card.fg
      bordered: true
      onClicked: if (card.svc) card.svc.signIn()
    }
    Button {
      // Closes the sign-in window; YouTube Music comes back signed out.
      visible: card.signingIn
      text: "Cancel"
      fontFamily: card.family
      foreground: card.fg
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    Button {
      visible: card.shown
      text: "Hide the window"
      fontFamily: card.family
      foreground: card.fg
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    Button {
      // Hiding also takes the engine back to the app from a sign-in page.
      visible: card.waiting && card.google && !card.shown && !card.signingIn
      text: "Back to YouTube Music"
      fontFamily: card.family
      foreground: card.fg
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    Button {
      visible: card.broken
      text: "Try again"
      fontFamily: card.family
      foreground: card.fg
      bordered: true
      onClicked: if (card.svc) card.svc.restartEngine()
    }
  }

  // ---- the cookie question
  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: card.asking
    spacing: Style.space(10)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Answer Google's cookie question"
      textFormat: Text.PlainText
      color: card.fg
      font.family: card.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(12)
      Button {
        text: "Reject all"
        fontFamily: card.family
        foreground: Color.accent
        bordered: true
        onClicked: if (card.svc) card.svc.answerCookies(false)
      }
      Button {
        text: "Accept all"
        fontFamily: card.family
        foreground: Color.accent
        bordered: true
        onClicked: if (card.svc) card.svc.answerCookies(true)
      }
    }
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(220)
      height: 1
      color: Util.alpha(card.fg, 0.2)
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Or:"
        textFormat: Text.PlainText
        color: Util.alpha(card.fg, 0.55)
        font.family: card.family
        font.pixelSize: Style.font.caption
      }
      Button {
        text: "Sign in with Google"
        fontFamily: card.family
        foreground: Util.alpha(card.fg, 0.75)
        onClicked: if (card.svc) card.svc.signIn()
      }
      Button {
        text: "Answer in the window"
        fontFamily: card.family
        foreground: Util.alpha(card.fg, 0.75)
        onClicked: if (card.svc) card.svc.showWindow()
      }
    }
  }
}
