import QtQuick

// state: signedout | waiting | cookie | failed | done
Item {
  id: c
  property string state: "signedout"
  property bool active: true
  width: 400; height: 330
  Glow { anchors.centerIn: parent; width: parent.width * 1.5; height: parent.height * 1.6; color: c.state === "failed" ? Theme.err : (c.state === "done" ? Theme.ok : Theme.accent); strength: 0.22 }
  Rectangle { anchors.fill: parent; radius: 24; color: Theme.raised; border.width: 1; border.color: Theme.hair }
  Column {
    anchors.centerIn: parent; width: parent.width - 56; spacing: 12
    Item { width: 62; height: 62; anchors.horizontalCenter: parent.horizontalCenter
      Rectangle { anchors.fill: parent; radius: 20; color: Theme.a(c.state === "failed" ? Theme.err : (c.state === "done" ? Theme.ok : Theme.accent), 0.16); border.width: 1; border.color: Theme.a(c.state === "failed" ? Theme.err : (c.state === "done" ? Theme.ok : Theme.accent), 0.45) }
      Icon { visible: c.state !== "waiting"; anchors.centerIn: parent; size: 26; name: c.state === "failed" ? "warn" : (c.state === "done" ? "check" : (c.state === "cookie" ? "globe" : "user")); color: c.state === "failed" ? Theme.err : (c.state === "done" ? Theme.ok : Theme.accent) }
      Spinner { visible: c.state === "waiting"; anchors.centerIn: parent; size: 34 } }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.fg; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold
      text: c.state === "signedout" ? "Sign in to YouTube Music" : c.state === "waiting" ? "Finish signing in" : c.state === "cookie" ? "Answer Google's cookie question" : c.state === "failed" ? "Sign-in did not finish" : "You are signed in" }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13
      text: c.state === "signedout" ? "Your library, likes and playlists need an account. Playing and search work without one."
        : c.state === "waiting" ? "A sign-in window is open. Solfa pauses the music and carries on when you are done."
        : c.state === "cookie" ? "Google shows this in the EU before the sign-in page."
        : c.state === "failed" ? "The window closed before Google said yes. Nothing was saved."
        : "Your library is loading. The music carries on from where it stopped." }
    Item { width: 1; height: 4 }
    Row { visible: c.state === "signedout"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
      Btn { kind: "primary"; icon: "user"; text: "Sign in" } Btn { text: "Not now" } }
    Row { visible: c.state === "waiting"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
      Btn { text: "Hide the window" } Btn { kind: "danger"; text: "Cancel" } }
    Column { visible: c.state === "cookie"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10; width: parent.width
      Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 10; Btn { text: "Reject all" } Btn { kind: "primary"; text: "Accept all" } }
      Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 8; Text { text: "Or:"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Btn { compact: true; kind: "ghost"; text: "Sign in with Google" } Btn { compact: true; kind: "ghost"; text: "Answer in the window" } } }
    Row { visible: c.state === "failed"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
      Btn { kind: "primary"; icon: "repeat"; text: "Try again" } Btn { text: "Back to YouTube Music" } }
    Row { visible: c.state === "done"; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10; Btn { kind: "primary"; text: "Done" } }
  }
}
