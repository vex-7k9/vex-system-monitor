import QtQuick
import Quickshell.Io

// Fan-speed and temperature monitor via lm_sensors. Polls `sensors -j` every
// 30 seconds for low overhead. Parses per-fan RPM and per-chip temperatures
// (CPU package, board sensors, NVMe).
QtObject {
  id: root

  property var fans: []
  property var temps: []
  property bool loaded: false
  property int interval: 30000
  property bool enabled: true

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
    if (!sensorsProc.running) sensorsProc.running = true
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
                newFans.push({ name: sname, rpm: Math.round(sval[fk]) })
            } else if (sname.indexOf("temp") === 0) {
              var tk = sname + "_input"
              if (sval.hasOwnProperty(tk)) {
                var t = sval[tk]
                if (t > -50 && t < 120)
                  newTemps.push({ name: "Board " + sname.replace("temp", ""), value: t.toFixed(1) })
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
                  newTemps.push({ name: "NVMe " + chip.slice(-4), value: t.toFixed(1) })
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
    command: ["sensors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSensors(text)
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
