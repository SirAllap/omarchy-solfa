import QtQuick
import QtTest
import Quickshell
import "views" as Views

// The real QueueView on a long list (test_queue_more.py): reaching the end
// of the rows, by the cursor or by scrolling, asks for the next page once,
// and nothing more is asked once the queue says there is no more. Every step
// is read back from the live items and logged as one "STATE {...}" line. The
// service is fake: it serves a queue of `total` invented songs and holds each
// queue.more reply until the scene answers it, as a slow network would.
ShellRoot {
  id: scene

  QtObject {
    id: fakeSvc
    signal queueChanged()
    property string videoId: "S0000000000"
    property int total: 50
    property bool more: true
    property var log: []
    property var pendingMore: null
    property string failMore: ""
    function song(i) {
      var id = "S" + ("0000000000" + i).slice(-10)
      return { kind: "song", videoId: id, title: "Song " + i, artists: [{ name: "The Examples", id: "" }], duration: 200, thumb: "", queueIndex: i }
    }
    function request(op, args, cb) {
      log.push({ op: op, args: args })
      if (op === "queue") {
        var items = []
        for (var i = 0; i < total; i++) items.push(song(i))
        cb({ ok: true, data: { items: items, automix: [], index: 0, more: more, version: log.length } })
      } else if (op === "queue.more") {
        if (failMore !== "") cb({ ok: false, error: failMore })
        else pendingMore = cb
      }
      return 0
    }
    // The page lands: the engine's store grows, then its queue event.
    function land(added, stillMore) {
      var cb = pendingMore
      pendingMore = null
      total += added
      more = stillMore
      cb({ ok: true, data: { added: added, more: stillMore } })
      queueChanged()
    }
  }

  FloatingWindow {
    id: win
    implicitWidth: 520
    implicitHeight: 480
    visible: true
    color: "transparent"

    // Three rows tall: the cursor reaches "three from the end" before the
    // end itself is on screen, so the two ways of asking are seen apart.
    Views.QueueView {
      id: view
      width: parent.width
      height: 140
      svc: fakeSvc
      active: true
    }

    TestCase { id: tc; name: "queue-more"; when: false }

    function asked() { return fakeSvc.log.filter(function (e) { return e.op === "queue.more" }).length }
    function list() {
      for (var i = 0; i < view.children.length; i++) if (view.children[i].positionViewAtEnd) return view.children[i]
      return null
    }
    function cursorId() { return view.current && view.current.item ? view.current.item.videoId : "" }

    // Past the view's 120 ms reload after a queue event.
    Timer { id: settle; interval: 300; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        var st = {}
        view.shown()
        win.after(function () {
          st.start = { rows: view.rows.length, more: view.queue.more, asked: win.asked() }
          // Down to three rows from the end asks; more Downs before the page lands ask nothing more.
          view.cursor = 44
          view.move(1); view.move(1)
          st.before = { cursor: view.cursor, asked: win.asked(), atYEnd: win.list().atYEnd }
          view.move(1)
          st.reached = { cursor: view.cursor, asked: win.asked(), args: fakeSvc.log[fakeSvc.log.length - 1].args }
          view.move(1); view.move(1); view.move(1)
          st.held = { cursor: view.cursor, asked: win.asked() }
          fakeSvc.land(49, true)
          win.after(function () {
            st.landed = { rows: view.rows.length, cursorId: win.cursorId(), asked: win.asked() }
            // Scrolling to the bottom asks for the next one.
            var l = win.list()
            l.positionViewAtEnd()
            st.scrolled = { atYEnd: l.atYEnd, asked: win.asked() }
            // A failed request may be asked again.
            fakeSvc.land(0, true)
            fakeSvc.failMore = "timeout"
            win.after(function () {
              view.cursor = view.rows.length - 2
              view.move(1)
              var first = win.asked()
              view.move(1)
              st.failed = { asked: win.asked(), retried: win.asked() - first }
              fakeSvc.failMore = ""
              view.move(1)
              // The last page: the queue says no more, and the end asks nothing.
              fakeSvc.land(10, false)
              win.after(function () {
                var before = win.asked()
                view.cursor = view.rows.length - 2
                view.move(1); view.move(1)
                win.list().positionViewAtBeginning()
                win.list().positionViewAtEnd()
                st.last = { rows: view.rows.length, more: view.queue.more, asked: win.asked() - before }
                console.log("STATE " + JSON.stringify(st))
                Qt.quit()
              })
            })
          })
        })
      }
    }
  }
}
