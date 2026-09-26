import QtQuick
import Quickshell.Io

// The connection to the bridge's socket, retried while down: every 700 ms
// for the first 10 s (a bridge that is starting), then every 3 s (each
// failed try logs one Quickshell warning).
//
// Every try is a NEW Socket. Quickshell's Socket (0.3.1) never connects
// again once a try has failed with "server not found" (no socket file yet,
// or a bridge restarting): setting `connected` back to true, even after
// false or a path change, does nothing. Reusing one left the panel on
// "Starting Solfa" for good after a bridge restart, while the bridge's
// orphan lease closed every new bridge 30 s later for want of a UI.
Item {
  id: root

  property string path: ""
  readonly property bool connected: sock !== null && sock.connected
  signal read(string data)

  property var sock: null
  property int tries: 0

  function write(text) { if (sock) sock.write(text) }
  function flush() { if (sock) sock.flush() }

  function retry() {
    if (sock !== null && sock.connected) return
    if (sock !== null) sock.destroy()
    tries++
    sock = socketComponent.createObject(root, { path: root.path })
  }

  Component {
    id: socketComponent
    Socket {
      connected: true
      parser: SplitParser {
        onRead: data => root.read(data)
      }
    }
  }

  onConnectedChanged: if (connected) tries = 0

  onPathChanged: if (sock !== null) { sock.destroy(); sock = null }

  Timer {
    interval: root.tries < 15 ? 700 : 3000
    repeat: true
    running: !root.connected && root.path !== ""
    triggeredOnStart: true
    onTriggered: root.retry()
  }
}
