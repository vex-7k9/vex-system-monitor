import QtQuick
import Quickshell.Io
import "ThermalData.js" as Thermal

// Polled CPU / GPU / NPU / RAM / swap / disk monitor.
//
// One atomic snapshot per tick: a single `sh -c` reads every source and emits
// `KEY=VALUE` lines, parsed once in parse(). The script is a compile-time
// constant — no user input, no QML interpolation — so it is safe to run in the
// shell session. All sources are world-readable /proc and /sys files plus df.
//
// A missing sysfs path prints the `NA` sentinel (never a bare 0) so a missing
// GPU/NPU device sets available=false and the meter hides, distinct from a real
// idle reading.
//
// Security: every collector has a wall-clock timeout (10 s) enforced by a Timer
// that calls kill(), and a byte ceiling (512 KiB) checked on streamFinished.
// External helpers use fixed absolute paths so a hijacked $PATH cannot redirect
// them.
QtObject {
  id: root

  // ---- public surface (bound by the meters row + hover card) ----
  property real cpuUsage: 0          // 0..1
  property int cpuFreqMhz: 0
  property int cpuMaxMhz: 0
  property int cpuTempC: 0           // CPU temp, °C (k10temp Tctl); 0 if unavailable
  property int gpuTempC: 0           // GPU temp, °C (nvidia-smi); 0 if unavailable
  property int cpuTempHigh: 0        // session-high CPU temp, °C (max seen since load)
  property int gpuTempHigh: 0        // session-high GPU temp, °C (max seen since load)
  property real memUsedKb: 0
  property real memTotalKb: 0
  property real swapUsedKb: 0
  property real swapTotalKb: 0
  property bool gpuAvailable: false
  property string gpuType: ""          // "intel" or "nvidia"
  property real gpuUsage: 0
  property int gpuFreqMhz: 0
  property int gpuMaxMhz: 0
  property real gpuMemUsedMb: 0
  property real gpuMemTotalMb: 0
  property bool npuAvailable: false
  property real npuUsage: 0
  property int npuFreqMhz: 0
  property int npuMaxMhz: 0
  property real npuMemBytes: 0        // NPU memory utilization (bytes)
  property string npuStatus: ""
  property real diskUsedKb: 0
  property real diskAvailKb: 0
  property real diskTotalKb: 0
  property int diskPct: 0
  property string diskSpeed: ""       // first NVMe link speed ("8.0 GT/s"); "" on non-NVMe

  property int interval: 3000
  property bool enabled: true

  // ---- security limits ----
  readonly property int _maxBytes: 524288   // 512 KiB — reject collector overflow
  readonly property int _timeoutMs: 10000  // 10 s wall-clock deadline per collector

  // ---- diff state (first sample records, second computes) ----
  property var prevCpu: null
  property real prevGpuIdle: -1
  property real prevGpuWall: 0
  property real prevNpuBusy: -1
  property real prevNpuWall: 0

  // ---- hardware model detection ----
  // Full thermal spec (idle/load/peak/tjMax) per detected hardware, sourced
  // from ThermalData.js. Falls back to generic envelopes when the model is
  // unknown, so the color scale and reference table always have sane values.
  property string cpuModel: ""
  property string gpuModel: ""
  property int cpuTjMax: Thermal.getDefaultCpu().tjMax
  property int gpuTjMax: Thermal.getDefaultGpu().tjMax
  property int cpuIdleTemp: Thermal.getDefaultCpu().idle
  property int cpuLoadTemp: Thermal.getDefaultCpu().load
  property int cpuPeakTemp: Thermal.getDefaultCpu().peak
  property int gpuIdleTemp: Thermal.getDefaultGpu().idle
  property int gpuLoadTemp: Thermal.getDefaultGpu().load
  property int gpuPeakTemp: Thermal.getDefaultGpu().peak

  // ---- resolved at startup by hwDetect ----
  property bool hwDetected: false            // true once parseHwDetect ran
  property bool hasNvidia: false             // GPU model matched NVIDIA
  readonly property int nvsmiEveryTicks: 3   // poll nvidia-smi every N ticks
  property int tickCount: 0
  property string cpuTempPath: "/sys/class/hwmon/hwmon1/temp1_input"  // resolved to k10temp/coretemp

  // Reset session-high temps (max seen since load) to 0.
  function resetSessionHigh() {
    root.cpuTempHigh = 0
    root.gpuTempHigh = 0
  }

  function refresh() {
    if (!pollProc.running) {
      root._g["poll"].armed = false
      pollProc.running = true
      pollWatchdog.restart()
    }
    if (!hwDetectProc.running) {
      root._g["hw"].armed = false
      hwDetectProc.running = true
      hwDetectWatchdog.restart()
    }
  }

  // QtObject has no default property in this Qt, so the Timer and Process are
  // declared as properties instead of children.
  property Timer pollTimer: Timer {
    interval: root.interval
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- Intel Lunar Lake sysfs layout (Arc iGPU tile0/gt0 + accel0 NPU). ----
  // QML has no triple-quoted strings, so the script is built from a list of
  // lines joined with \n. Every value is a space-separated run of tokens (no
  // glob chars, no embedded spaces), so unquoted `echo` is word-splitting-safe
  // and prints single-spaced. The single quotes inside the awk programs are
  // literal inside these QML strings.
  //
  // The script is regenerated whenever hardware detection resolves (hwmon
  // path, NVIDIA presence), and nvidia-smi is only queried every N ticks on
  // NVIDIA machines — never on AMD/Intel-only systems. sysfs reads use the
  // shell `read` builtin instead of forking cat/head per file, and meminfo is
  // folded into one awk pass, to keep each tick to ~3 forks total.
  //
  // Fixed absolute paths so a hijacked $PATH cannot redirect helpers.
  function _snapshotLines() {
    var lines = [
      "LANG=C",
      "{",
      "  read -r _ u n s i io irq so < /proc/stat; echo cpu=cpu $u $n $s $i $io $irq $so",
      "  read -r cur < /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq || cur=NA; echo cur=$cur",
      "  read -r cmax < /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq || cmax=NA; echo cmax=$cmax",
      "  read -r ctemp < " + root.cpuTempPath + " || ctemp=NA; echo ctemp=$ctemp",
      "  echo mem=$(/usr/bin/awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ {print $1, $2}' /proc/meminfo)",
      "  read -r gact < /sys/class/drm/card0/device/tile0/gt0/freq0/act_freq || gact=NA; echo gact=$gact",
      "  read -r gmax < /sys/class/drm/card0/device/tile0/gt0/freq0/max_freq || gmax=NA; echo gmax=$gmax",
      "  read -r gidle < /sys/class/drm/card0/device/tile0/gt0/gtidle/idle_residency_ms || gidle=NA; echo gidle=$gidle"
    ]
    if (!root.hwDetected || (root.hasNvidia && root.tickCount % root.nvsmiEveryTicks === 0)) {
      lines.push("  echo nvsmi=$(/usr/bin/nvidia-smi --query-gpu=utilization.gpu,clocks.current.graphics,clocks.max.graphics,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo NA)")
    }
    lines = lines.concat([
      "  read -r nbusy < /sys/class/accel/accel0/device/npu_busy_time_us || nbusy=NA; echo nbusy=$nbusy",
      "  read -r nstat < /sys/class/accel/accel0/device/power/runtime_status || nstat=NA; echo nstat=$nstat",
      "  read -r ncur < /sys/class/accel/accel0/device/npu_current_frequency_mhz || ncur=NA; echo ncur=$ncur",
      "  read -r nmax < /sys/class/accel/accel0/device/npu_max_frequency_mhz || nmax=NA; echo nmax=$nmax",
      "  read -r nmem < /sys/class/accel/accel0/device/npu_memory_utilization || nmem=NA; echo nmem=$nmem",
      "  echo disk=$(/usr/bin/df -P / | /usr/bin/awk 'NR==2 {print $2, $3, $4, $5}')",
      // Cap stdout at the producer: the collector can never buffer more than
      // this even if a helper misbehaves or storms output.
      "} 2>/dev/null | /usr/bin/head -c 1048576"
    ])
    return lines
  }

  property string snapshotScript: root._snapshotLines().join("\n")

  // ---- process-group teardown engine ----
  //
  // Each producer (poll / clock / hwDetect) is created under setsid so its
  // leader PID == PGID. Teardown is instance-bound: every producer has its own
  // armed state + deadline watchdog, so a concurrent teardown is never dropped
  // by a shared half-open killer. One shared killProc worker serializes the
  // actual shell passes.
  //
  // PID-reuse safety: bash reads /proc/<pgid>/stat field 22 (starttime) and we
  // pass back the value seen at arm time; before every signal bash re-checks
  // that the live starttime still equals it. A group whose leader was reaped
  // and replaced by an unrelated process is treated as GONE and never touched.
  // The deadline keeps firing (repeat=true) until the group is actually
  // reaped — stream-close alone does not clear it.
  property var _g: ({
    poll:  { armed: false, pgid: "", start: "", block: false },
    clock: { armed: false, pgid: "", start: "", block: false },
    hw:    { armed: false, pgid: "", start: "", block: false }
  })
  property var _gWatch: ({
    poll: root.pollWatchdog, clock: root.clockWatchdog, hw: root.hwDetectWatchdog
  })

  property Process killProc: Process {
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = String(text || "").trim()
        var c = root._stepFor
        root._stepFor = ""
        var st = root._g[c]
        if (!st) return
        if (status.indexOf("GONE") === 0) {
          st.armed = false
          root._gWatch[c].stop()
        } else if (status.indexOf("START=") === 0) {
          st.start = status.substring(6).trim()
        }
      }
    }
  }

  // Run one bash pass for producer c with the given signal. want = expected
  // starttime ("" on first arm). Outputs GONE when the group is absent or
  // reused, else START=<starttime>.
  function _step(c, sig) {
    var st = root._g[c]
    if (!st.armed || !st.pgid) return
    if (root.killProc.running) return
    root._stepFor = c
    root.killProc.command = [
      "/bin/sh", "-c",
      "pid=$1; want=$2; sig=$3\n" +
      "f=/proc/$pid/stat\n" +
      "[ -e \"$f\" ] || { echo GONE; exit 0; }\n" +
      "start=$(/usr/bin/awk '{print $22}' \"$f\" 2>/dev/null || true)\n" +
      "[ -n \"$want\" ] && [ \"$start\" != \"$want\" ] && { echo GONE; exit 0; }\n" +
      "kill -$sig -- -$pid 2>/dev/null || true\n" +
      "echo START=$start",
      "grpkill", st.pgid, st.start, sig
    ]
    root.killProc.running = true
  }

  // Arm teardown for a producer: record pgid and TERM its group; the deadline
  // watchdog thereafter escalates and keeps going until the group is reaped.
  function killProcessGroup(tgt) {
    var c = ""
    if (tgt === root.pollProc) c = "poll"
    else if (tgt === root.clockProc) c = "clock"
    else if (tgt === root.hwDetectProc) c = "hw"
    if (!c) return
    var st = root._g[c]
    if (st.armed) return
    st.armed = true
    st.pgid = String(tgt.processId || "")
    if (st.pgid === "") { st.armed = false; return }
    st.start = ""
    root._gWatch[c].restart()
    root._step(c, "TERM")
  }

  // A producer's stream closed. Do NOT treat that as teardown completion — a
  // descendant can outlive the capped head, so leave the deadline watchdog to
  // confirm the group is truly reaped (escalating TERM -> KILL as needed).
  // pgid is taken from the value recorded at onStarted (processId is invalid
  // once the stream has already closed), never re-read here.
  function _onDone(c) {
    var st = root._g[c]
    if (st.armed) return
    var g = root._g[c]
    if (g.pgid === "") { g.armed = false; return }
    st.armed = true
    g.start = ""
    root._gWatch[c].restart()
    root._step(c, "TERM")
  }
  // Record a producer's group id at launch (processId is only valid while
  // running); teardown later re-uses this so it never reads a cleared pid.
  function _captureStart(c, proc) {
    var pid = String(proc.processId || "")
    if (pid) root._g[c].pgid = pid
  }

  // Durable reaping: launch the KILL detached so it survives this service being
  // destroyed alongside the widget (a non-detached child Process would be
  // cancelled with the object). Identity (starttime) is still verified in bash.
  function _reapAll() {
    var order = ["poll", "clock", "hw"]
    for (var i = 0; i < order.length; i++) {
      var c = order[i]
      var st = root._g[c]
      if (!st.armed || !st.pgid) continue
      root._gWatch[c].stop()
      root.killProc.command = [
        "/bin/sh", "-c",
        "pid=$1; want=$2\n" +
        "f=/proc/$pid/stat\n" +
        "[ -e \"$f\" ] || exit 0\n" +
        "start=$(/usr/bin/awk '{print $22}' \"$f\" 2>/dev/null || true)\n" +
        "[ -n \"$want\" ] && [ \"$start\" != \"$want\" ] && exit 0\n" +
        "kill -KILL -- -$pid 2>/dev/null || true",
        "grpkill", st.pgid, st.start
      ]
      root.killProc.startDetached()
    }
  }

  Component.onDestruction: {
    root._reapAll()
  }

  property Timer pollWatchdog: Timer {
    interval: root._timeoutMs
    repeat: true
    onTriggered: {
      var st = root._g["poll"]
      if (!st.armed) {
        // Timeout: producer is still running past its deadline.
        if (root.pollProc.running) root.killProcessGroup(root.pollProc)
        else stop()
      } else root._step("poll", "KILL")
    }
  }

  property Process pollProc: Process {
    // setsid detaches the whole job into its own process group so the watchdog
    // can kill the group -- the shell and every helper it spawned -- instead of
    // only the direct child. Command is fully absolute (no $PATH lookups).
    command: ["/usr/bin/setsid", "/bin/sh", "-c", root.snapshotScript]
    onStarted: root._captureStart("poll", root.pollProc)
    stdout: StdioCollector {
      id: pollOutput
      waitForEnd: true
      onStreamFinished: {
        root._onDone("poll")
        if (pollOutput.data.length > root._maxBytes) return
        root.parse(pollOutput.text)
      }
    }
  }

  // Static clock read (NVMe link speed) — one-shot at startup, not per poll.
  // The NVMe link speed comes from sysfs and needs no privileges. DIMM
  // configured speed has no sudo-free source (SMBIOS needs dmidecode/root),
  // so the RAM freq column always shows "—".
  readonly property string clockScript: [
    "LANG=C",
    "{",
    "  echo ssd=$(/usr/bin/cat /sys/class/nvme/nvme*/device/current_link_speed 2>/dev/null | /usr/bin/head -1)",
    "} 2>/dev/null | /usr/bin/head -c 4096"
  ].join("\n")

  property Process clockProc: Process {
    command: ["/usr/bin/setsid", "/bin/sh", "-c", root.clockScript]
    onStarted: root._captureStart("clock", root.clockProc)
    stdout: StdioCollector {
      id: clockOutput
      waitForEnd: true
      onStreamFinished: {
        root._onDone("clock")
        if (clockOutput.data.length > root._maxBytes) return
        root.parseClocks(clockOutput.text)
      }
    }
  }

  property Timer clockWatchdog: Timer {
    interval: root._timeoutMs
    repeat: true
    onTriggered: {
      var st = root._g["clock"]
      if (!st.armed) {
        if (root.clockProc.running) root.killProcessGroup(root.clockProc)
        else stop()
      } else root._step("clock", "KILL")
    }
  }

  function parseClocks(text) {
    const raw = {}
    const lines = (text || "").split("\n")
    for (const line of lines) {
      const i = line.indexOf("=")
      if (i < 0) continue
      raw[line.slice(0, i)] = line.slice(i + 1)
    }
    // Trim the trailing " PCIe" so "8.0 GT/s PCIe" fits the freq column.
    root.diskSpeed = root.boundText(String(raw.ssd || "").replace(/\s*PCIe$/, "").trim(), 48)
  }

  // Bounded text: strip control characters (including embedded HTML/CRLF) and
  // cap the length so external strings stay display-safe and small.
  function boundText(s, max) {
    var t = String(s || "").replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim()
    return t.length > max ? t.slice(0, max) : t
  }

  Component.onCompleted: {
    root._g["clock"].armed = false
    clockProc.running = true
    clockWatchdog.restart()
  }

  // ---- hardware detection script ----
  // Fixed absolute paths. nvidia-smi is primary; falls back to lspci so AMD /
  // Intel / unknown GPUs still get a model string for the thermal lookup table.
  // Output is capped (head -1) so the collector stays bounded. Also resolves
  // the CPU temp hwmon (k10temp/coretemp) so the snapshot reads the right
  // sensor regardless of sysfs numbering.
  readonly property string hwDetectScript: [
    "LANG=C",
    "{",
    "  echo cpumodel=$(/usr/bin/grep -m1 'model name' /proc/cpuinfo | /usr/bin/cut -d: -f2 | /usr/bin/xargs)",
    "  echo gpumodel=$(/usr/bin/nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null ||",
    "    /usr/bin/lspci 2>/dev/null | /usr/bin/grep -E 'VGA|3D' | /usr/bin/head -1 | /usr/bin/awk -F': ' '{print $2}' ||",
    "    echo NA)",
    "  hwmonp=$(for d in /sys/class/hwmon/hwmon*; do",
    "      n=$(/usr/bin/cat \"$d/name\" 2>/dev/null)",
    "      case \"$n\" in k10temp|coretemp) echo \"$d/temp1_input\"; break;; esac",
    "    done)",
    "  echo hwmonp=${hwmonp:-NA}",
    "} 2>/dev/null | /usr/bin/head -c 16384"
  ].join("\n")

  property Process hwDetectProc: Process {
    command: ["/usr/bin/setsid", "/bin/sh", "-c", root.hwDetectScript]
    onStarted: root._captureStart("hw", root.hwDetectProc)
    stdout: StdioCollector {
      id: hwDetectOutput
      waitForEnd: true
      onStreamFinished: {
        root._onDone("hw")
        if (hwDetectOutput.data.length > root._maxBytes) return
        root.parseHwDetect(hwDetectOutput.text)
      }
    }
  }

  property Timer hwDetectWatchdog: Timer {
    interval: root._timeoutMs
    repeat: true
    onTriggered: {
      var st = root._g["hw"]
      if (!st.armed) {
        if (root.hwDetectProc.running) root.killProcessGroup(root.hwDetectProc)
        else stop()
      } else root._step("hw", "KILL")
    }
  }

  function parseHwDetect(text) {
    const raw = {}
    const lines = (text || "").split("\n")
    for (const line of lines) {
      const i = line.indexOf("=")
      if (i < 0) continue
      raw[line.slice(0, i)] = line.slice(i + 1)
    }
    root.cpuModel = root.boundText(String(raw.cpumodel || ""), 96)
    root.gpuModel = root.boundText(String(raw.gpumodel || ""), 96)

    // Resolve the CPU temp sensor path (k10temp/coretemp) and whether an
    // NVIDIA GPU is present — gates nvidia-smi polling in the snapshot.
    root.cpuTempPath = root.boundText((raw.hwmonp && raw.hwmonp !== "NA")
      ? raw.hwmonp
      : "/sys/class/hwmon/hwmon1/temp1_input", 512)
    root.hasNvidia = root.gpuModel.toLowerCase().indexOf("nvidia") >= 0 || root.gpuModel.toLowerCase().indexOf("geforce") >= 0
    root.hwDetected = true

    // Real-world thermal spec for the detected hardware (idle/load/peak/
    // tjMax). Falls back to generic envelopes when the model is unknown.
    const cth = Thermal.detectCpu(root.cpuModel)
    const gth = Thermal.detectGpu(root.gpuModel)
    root.cpuIdleTemp = cth.idle
    root.cpuLoadTemp = cth.load
    root.cpuPeakTemp = cth.peak
    root.cpuTjMax = cth.tjMax
    root.gpuIdleTemp = gth.idle
    root.gpuLoadTemp = gth.load
    root.gpuPeakTemp = gth.peak
    root.gpuTjMax = gth.tjMax
  }

  function parse(text) {
    const raw = {}
    const lines = (text || "").split("\n")
    for (let line of lines) {
      const i = line.indexOf("=")
      if (i < 0) continue
      raw[line.slice(0, i)] = line.slice(i + 1)
    }
    const now = Date.now()
    root.tickCount = (root.tickCount + 1) % root.nvsmiEveryTicks

    // CPU: aggregate /proc/stat delta. Fields after the "cpu" token are
    // user nice system idle iowait irq softirq — idle is index 4.
    const c = (raw.cpu || "").trim().split(/\s+/)
    if (c.length >= 8) {
      const idle = parseInt(c[4]) || 0
      const total = (parseInt(c[1]) || 0) + (parseInt(c[2]) || 0) + (parseInt(c[3]) || 0)
        + idle + (parseInt(c[5]) || 0) + (parseInt(c[6]) || 0) + (parseInt(c[7]) || 0)
      if (root.prevCpu) {
        const dT = total - root.prevCpu.total
        const dI = idle - root.prevCpu.idle
        root.cpuUsage = dT > 0 ? Math.max(0, Math.min(1, 1 - dI / dT)) : 0
      }
      root.prevCpu = { total: total, idle: idle }
    }
    root.cpuFreqMhz = Math.round((parseInt(raw.cur) || 0) / 1000)   // kHz -> MHz
    root.cpuMaxMhz = Math.round((parseInt(raw.cmax) || 0) / 1000)
    // k10temp reports millidegrees C (e.g. 55625 -> 55°C). Round to integer °C.
    root.cpuTempC = Math.round((parseFloat(raw.ctemp) || 0) / 1000)
    if (root.cpuTempC > root.cpuTempHigh) root.cpuTempHigh = root.cpuTempC

    // Memory / swap (KB)
    let mt = 0, ma = 0, st = 0, sf = 0
    const mems = (raw.mem || "").match(/MemTotal:\s*\d+|MemAvailable:\s*\d+|SwapTotal:\s*\d+|SwapFree:\s*\d+/g) || []
    for (const m of mems) {
      const bits = m.split(/\s+/)
      const n = parseInt(bits[1]) || 0
      if (bits[0] === "MemTotal:") mt = n
      else if (bits[0] === "MemAvailable:") ma = n
      else if (bits[0] === "SwapTotal:") st = n
      else if (bits[0] === "SwapFree:") sf = n
    }
    root.memTotalKb = mt
    root.memUsedKb = Math.max(0, mt - ma)
    root.swapTotalKb = st
    root.swapUsedKb = Math.max(0, st - sf)

    // GPU: try Intel sysfs first, fall back to nvidia-smi. On NVIDIA systems the
    // snapshot only includes an nvsmi line every nvsmiEveryTicks ticks, so
    // between polls we keep the last good readings instead of zeroing them.
    const gidle = parseFloat(raw.gidle)
    const nvLine = raw.hasOwnProperty("nvsmi")
    const nvRaw = (nvLine ? raw.nvsmi : "").trim()
    root.gpuMaxMhz = parseInt(raw.gmax) || 0
    root.gpuFreqMhz = parseInt(raw.gact) || 0
    root.gpuMemUsedMb = 0
    root.gpuMemTotalMb = 0

    if (!isNaN(gidle) && root.gpuMaxMhz > 0) {
      // Intel GPU
      root.gpuType = "intel"
      root.gpuAvailable = true
      if (root.prevGpuIdle >= 0 && root.prevGpuWall > 0) {
        const wall = now - root.prevGpuWall
        const dI = gidle - root.prevGpuIdle
        if (wall > 0 && dI >= 0) root.gpuUsage = Math.max(0, Math.min(1, 1 - dI / wall))
      }
      root.prevGpuIdle = gidle
      root.prevGpuWall = now
    } else if (nvLine && nvRaw !== "NA" && nvRaw !== "") {
      // NVIDIA GPU via nvidia-smi:
      // "util%, clk_mhz, max_mhz, mem_used_MiB, mem_total_MiB, temp_C"
      const parts = nvRaw.split(",").map(function(s) { return s.trim() })
      if (parts.length >= 6) {
        root.gpuType = "nvidia"
        root.gpuAvailable = true
        root.gpuUsage = (parseFloat(parts[0]) || 0) / 100
        root.gpuFreqMhz = parseInt(parts[1]) || 0
        root.gpuMaxMhz = parseInt(parts[2]) || 0
        root.gpuMemUsedMb = parseFloat(parts[3]) || 0
        root.gpuMemTotalMb = parseFloat(parts[4]) || 0
        root.gpuTempC = parseInt(parts[5]) || 0
        if (root.gpuTempC > root.gpuTempHigh) root.gpuTempHigh = root.gpuTempC
      }
      root.prevGpuIdle = -1
      root.prevGpuWall = now
    } else if (root.hasNvidia) {
      // NVIDIA GPU but nvsmi not polled this tick — keep last readings.
      root.prevGpuWall = now
    } else {
      root.gpuType = ""
      root.gpuAvailable = false
      root.gpuUsage = 0
      root.prevGpuIdle = -1
    }

    // NPU usage via npu_busy_time_us delta; busy counter freezes while suspended.
    const nbusy = parseFloat(raw.nbusy)
    root.npuMaxMhz = parseInt(raw.nmax) || 0
    root.npuFreqMhz = parseInt(raw.ncur) || 0
    root.npuMemBytes = parseFloat(raw.nmem) || 0
    root.npuStatus = (raw.nstat || "").trim()
    root.npuAvailable = !isNaN(nbusy) && root.npuMaxMhz > 0
    if (root.npuAvailable) {
      if (root.prevNpuBusy >= 0 && root.prevNpuWall > 0) {
        const wallUs = (now - root.prevNpuWall) * 1000
        const d = nbusy - root.prevNpuBusy
        if (wallUs > 0 && d >= 0) root.npuUsage = Math.max(0, Math.min(1, d / wallUs))
      }
      if (root.npuStatus === "suspended") root.npuUsage = 0
      root.prevNpuBusy = nbusy
      root.prevNpuWall = now
    } else {
      root.npuUsage = 0
      root.prevNpuBusy = -1
    }

    // Disk: `df -P /` prints "total used avail pct%". On a btrfs root this is
    // the subvolume allocation, so used + free != total (reserved space).
    const d = (raw.disk || "").trim().split(/\s+/)
    if (d.length >= 4) {
      root.diskTotalKb = parseFloat(d[0]) || 0
      root.diskUsedKb = parseFloat(d[1]) || 0
      root.diskAvailKb = parseFloat(d[2]) || 0
      root.diskPct = parseInt(d[3]) || 0
    }
  }
}
