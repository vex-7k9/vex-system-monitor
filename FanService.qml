import QtQuick
import Quickshell.Io

// Fan-speed and temperature monitor via lm_sensors. Polls `sensors -j` every
// 30 seconds for low overhead. Parses per-fan RPM and per-chip temperatures
// (CPU package, board sensors, NVMe).
//
// Security: the helper runs inside a setsid process group with its stdout
// capped at the producer (head -c), a 10 s wall-clock watchdog that kills the
// whole group, and a byte ceiling kept as defense in depth. Sensor names are
// bounded and control-char-stripped before rendering. Fixed absolute paths so
// a hijacked $PATH cannot redirect any executable.
QtObject {
  id: root

  property var fans: []
  property var temps: []
  property bool loaded: false
  property int interval: 30000
  property bool enabled: true

  // ---- security limits ----
  readonly property int _maxBytes: 524288   // 512 KiB — reject collector overflow
  readonly property int _timeoutMs: 10000  // 10 s wall-clock deadline

  // Bounded text: strip control characters and cap length for display-safe names.
  function boundText(s, max) {
    var t = String(s || "").replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim()
    return t.length > max ? t.slice(0, max) : t
  }

  readonly property bool hasDeadFan: {
    var f = fans
    for (var i = 0; i < f.length; i++) { if (f[i].rpm === 0) return true }
    return false
  }

  readonly property real worstTemp: {
    var w = -999
    for (var i = 0; i < temps.length; i++) {
      var v = parseFloat(temps[i].value)
      if (v > w) w = v
    }
    return w
  }

  function refresh() {
    if (!sensorsProc.running) {
      sensorsProc.running = true
      sensorsWatchdog.restart()
    }
  }

  function parseSensors(raw) {
    try {
      var data = JSON.parse(raw)
      var newFans = []
      var newTemps = []
      var chips = Object.keys(data)

      for (var ci = 0; ci < chips.length; ci++) {
        var chip = chips[ci]
        var chipData = data[chip]
        if (typeof chipData !== "object" || chipData === null) continue
        var skeys = Object.keys(chipData)

        if (chip.indexOf("it8689") !== -1 || chip.indexOf("it87") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue

            if (sname.indexOf("fan") === 0) {
              var fk = sname + "_input"
              if (sval.hasOwnProperty(fk))
                newFans.push({ name: root.boundText(sname, 32), rpm: Math.round(sval[fk]) })
            } else if (sname.indexOf("temp") === 0) {
              var tk = sname + "_input"
              if (sval.hasOwnProperty(tk)) {
                var t = sval[tk]
                if (t > -50 && t < 120)
                  newTemps.push({ name: "Board " + root.boundText(sname.replace("temp", ""), 28), value: t.toFixed(1) })
              }
            }
          }
        } else if (chip.indexOf("coretemp") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Package id 0") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                newTemps.unshift({ name: "CPU", value: sval[vkeys[ki]].toFixed(1) })
                break
              }
            }
          }
        } else if (chip.indexOf("nvme") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Composite") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                var t = sval[vkeys[ki]]
                if (t > -50 && t < 100)
                  newTemps.push({ name: "NVMe " + root.boundText(chip.slice(-4), 16), value: t.toFixed(1) })
                break
              }
            }
          }
        }
      }

      fans = newFans
      temps = newTemps
      loaded = true
    } catch (e) { /* keep last good value */ }
  }

  property Process sensorsProc: Process {
    // setsid -> own process group (group id == processId) so the watchdog can
    // kill the helper and every descendant; head -c bounds the stream at the
    // producer so the collector never buffers unbounded output.
    command: ["/usr/bin/setsid", "/bin/sh", "-c", "/usr/bin/sensors -j | /usr/bin/head -c 524288"]
    // Record the group id at launch (processId is invalid after the stream
    // closes); teardown re-uses this so it never reads a cleared pid.
    onStarted: { var p = String(sensorsProc.processId || ""); if (p) root._pgid = p }
    stdout: StdioCollector {
      id: sensorsOutput
      waitForEnd: true
      onStreamFinished: {
        root._onDone()
        if (sensorsOutput.data.length > root._maxBytes) return
        root.parseSensors(text)
      }
    }
  }

  property Process fanKillProc: Process {
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = String(text || "").trim()
        if (status.indexOf("GONE") === 0) {
          root._armed = false
          root.sensorsWatchdog.stop()
        }
      }
    }
  }

  property bool _armed: false
  property string _pgid: ""
  property string _start: ""

  // One bash pass: verify the group still exists at the recorded starttime
  // (PID-reuse safety), else GONE; otherwise signal and report the live
  // starttime. TERM first, KILL on escalation — the reuse window on an
  // unrelated later group is closed by the identity check below.
  function _fsStep(sig) {
    if (!root._pgid) return
    if (root.fanKillProc.running) return
    root.fanKillProc.command = [
      "/bin/sh", "-c",
      "pid=$1; want=$2; sig=$3\n" +
      "f=/proc/$pid/stat\n" +
      "[ -e \"$f\" ] || { echo GONE; exit 0; }\n" +
      "start=$(/usr/bin/awk '{print $22}' \"$f\" 2>/dev/null || true)\n" +
      "[ -n \"$want\" ] && [ \"$start\" != \"$want\" ] && { echo GONE; exit 0; }\n" +
      "kill -$sig -- -$pid 2>/dev/null || true\n" +
      "echo START=$start",
      "grpkill", root._pgid, root._start, sig
    ]
    root.fanKillProc.running = true
  }

  function killProcessGroup() {
    if (root._armed) return
    root._armed = true
    if (!root._pgid) { root._armed = false; return }
    root._start = ""
    root.sensorsWatchdog.restart()
    root._fsStep("TERM")
  }

  // A producer's stream closed. Do NOT treat that as completion — a descendant
  // can outlive the capped head, so arm and TERM the (still real) group; the
  // deadline watchdog escalates to KILL until it is truly reaped. pgid comes
  // from onStarted, never re-read from a cleared processId.
  function _onDone() {
    if (root._armed) return
    if (!root._pgid) return
    root._armed = true
    root._start = ""
    root.sensorsWatchdog.restart()
    root._fsStep("TERM")
  }

  property Timer sensorsWatchdog: Timer {
    id: _fsWatchdog
    interval: root._timeoutMs
    repeat: true
    onTriggered: {
      if (!root._armed) {
        if (sensorsProc.running) root.killProcessGroup()
        else stop()
      } else root._fsStep("KILL")
    }
  }

  // Durable teardown: if a group is still armed when this component is
  // destroyed, launch the KILL detached so it survives the component teardown
  // (a non-detached child Process would be cancelled with the object).
  Component.onDestruction: {
    if (root._armed && root._pgid) {
      root.sensorsWatchdog.stop()
      if (root.fanKillProc.running) return
      var pid = root._pgid
      var want = root._start
      root.fanKillProc.command = [
        "/bin/sh", "-c",
        "pid=$1; want=$2\n" +
        "f=/proc/$pid/stat\n" +
        "[ -e \"$f\" ] || exit 0\n" +
        "start=$(/usr/bin/awk '{print $22}' \"$f\" 2>/dev/null || true)\n" +
        "[ -n \"$want\" ] && [ \"$start\" != \"$want\" ] && exit 0\n" +
        "kill -KILL -- -$pid 2>/dev/null || true",
        "grpkill", pid, want
      ]
      root.fanKillProc.startDetached()
    }
  }

  property Timer pollTimer: Timer {
    interval: root.interval
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
