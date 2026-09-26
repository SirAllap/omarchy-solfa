import QtQuick
import Quickshell
import "lib"

// Drives lib/BridgeSocket.qml against tests/test_bridge_socket.py's fake
// bridge: every connect, drop and line it sees goes to the log.
ShellRoot {
  BridgeSocket {
    id: link
    path: Quickshell.env("SOLFA_SOCKET_PATH")
    onConnectedChanged: {
      console.log("LINK " + (link.connected ? "up" : "down"))
      if (link.connected) { link.write("{\"hello\":1}\n"); link.flush() }
    }
    onRead: data => console.log("LINE " + data)
  }
  Timer {
    interval: Number(Quickshell.env("SOLFA_SCENE_MS") || "9000")
    running: true
    onTriggered: Qt.quit()
  }
}
