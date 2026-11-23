import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "views" as Views

// NowPlaying and QueueView with svc null, as at shell start (test_null_svc.py):
// the panel is built before the Service exists. Any binding that reads a
// property of svc without checking it logs a TypeError; the test fails on
// any TypeError. Then svc is set to a starting service and back to null.
ShellRoot {
  id: scene

  QtObject {
    id: startingSvc
    signal queueChanged()
    property bool starting: true
    property bool hasTrack: false
    property bool ready: true
    property bool closed: false
    property string engineLine: ""
    property string videoId: ""
    property var settings: ({})
    property int fastClockUsers: 0
    function request(op, args, cb) {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 520
    implicitHeight: 600
    visible: true
    color: "transparent"
    Column {
      anchors.fill: parent
      Views.NowPlaying { id: np; width: parent.width; svc: null }
      Views.QueueView { id: qv; width: parent.width; height: 200; svc: null; active: true }
    }
  }

  Timer {
    interval: 400; running: true
    onTriggered: {
      var st = { nullFull: np.full, nullLoading: qv.loading }
      np.svc = startingSvc; qv.svc = startingSvc
      st.startFull = np.full
      np.svc = null; qv.svc = null
      console.log("STATE " + JSON.stringify(st))
      Qt.quit()
    }
  }
}
