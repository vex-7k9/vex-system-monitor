import QtQuick
import Quickshell.Io

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
QtObject {
  id: root

  // ---- public surface (bound by the meters row + hover card) ----
  property real cpuUsage: 0          // 0..1
  property int cpuFreqMhz: 0
  property int cpuMaxMhz: 0
  property int cpuTempC: 0           // CPU temp, °C (k10temp Tctl); 0 if unavailable
  property int gpuTempC: 0           // GPU temp, °C (nvidia-smi); 0 if unavailable
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
  property string memSpeed: ""        // DRAM configured speed ("8533 MT/s"); via dmidecode, "" if unavailable
  property string diskSpeed: ""       // first NVMe link speed ("8.0 GT/s"); "" on non-NVMe

  property int interval: 3000
  property bool enabled: true

  // ---- diff state (first sample records, second computes) ----
  property var prevCpu: null
  property real prevGpuIdle: -1
  property real prevGpuWall: 0
  property real prevNpuBusy: -1
  property real prevNpuWall: 0

  // ---- hardware model detection ----
  property string cpuModel: ""
  property string gpuModel: ""
  property int cpuTjMax: 95   // default AMD TjMax
  property int gpuTjMax: 93   // default NVIDIA TjMax

  function refresh() {
    if (!pollProc.running) pollProc.running = true
    if (!hwDetectProc.running) hwDetectProc.running = true
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

  // Intel Lunar Lake sysfs layout (Arc iGPU tile0/gt0 + accel0 NPU).
  // QML has no triple-quoted strings, so the script is a list of lines joined
  // with \n. The inner double quotes are omitted — every value is a space-
  // separated run of tokens (no glob chars, no embedded spaces), so unquoted
  // `echo $(...)` is word-splitting-safe and prints single-spaced. The single
  // quotes inside the awk/grep programs are literal inside these QML strings.
  readonly property string snapshotScript: [
    "LANG=C",
    "{",
    "  echo cpu=$(head -1 /proc/stat)",
    "  echo cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo NA)",
    "  echo cmax=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo NA)",
    "  echo ctemp=$(cat /sys/class/hwmon/hwmon1/temp1_input 2>/dev/null || echo NA)",
    "  echo mem=$(grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo | xargs)",
    "  echo gact=$(cat /sys/class/drm/card0/device/tile0/gt0/freq0/act_freq 2>/dev/null || echo NA)",
    "  echo gmax=$(cat /sys/class/drm/card0/device/tile0/gt0/freq0/max_freq 2>/dev/null || echo NA)",
    "  echo gidle=$(cat /sys/class/drm/card0/device/tile0/gt0/gtidle/idle_residency_ms 2>/dev/null || echo NA)",
    "  echo nvsmi=$(nvidia-smi --query-gpu=utilization.gpu,clocks.current.graphics,clocks.max.graphics,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo NA)",
    "  echo nbusy=$(cat /sys/class/accel/accel0/device/npu_busy_time_us 2>/dev/null || echo NA)",
    "  echo nstat=$(cat /sys/class/accel/accel0/device/power/runtime_status 2>/dev/null || echo NA)",
    "  echo ncur=$(cat /sys/class/accel/accel0/device/npu_current_frequency_mhz 2>/dev/null || echo NA)",
    "  echo nmax=$(cat /sys/class/accel/accel0/device/npu_max_frequency_mhz 2>/dev/null || echo NA)",
    "  echo nmem=$(cat /sys/class/accel/accel0/device/npu_memory_utilization 2>/dev/null || echo NA)",
    "  echo disk=$(df -P / | awk 'NR==2 {print $2, $3, $4, $5}')",
    "}"
  ].join("\n")

  property Process pollProc: Process {
    command: ["sh", "-c", root.snapshotScript]
    stdout: StdioCollector {
      id: pollOutput
      waitForEnd: true
      onStreamFinished: root.parse(pollOutput.text)
    }
  }

  // Static clock reads (DRAM speed, NVMe link speed) — one-shot at startup,
  // not per poll. RAM speed needs dmidecode + passwordless sudo (`sudo -n`
  // never prompts); both fall back to "" so the freq column shows "—".
  readonly property string clockScript: [
    "LANG=C",
    "{",
    "  echo memspeed=$(sudo -n dmidecode -t memory 2>/dev/null | awk -F: '/Configured Memory Speed/ {print $2; exit}')",
    "  echo ssd=$(cat /sys/class/nvme/nvme*/device/current_link_speed 2>/dev/null | head -1)",
    "}"
  ].join("\n")

  property Process clockProc: Process {
    command: ["sh", "-c", root.clockScript]
    stdout: StdioCollector {
      id: clockOutput
      waitForEnd: true
      onStreamFinished: root.parseClocks(clockOutput.text)
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
    root.memSpeed = String(raw.memspeed || "").trim()
    // Trim the trailing " PCIe" so "8.0 GT/s PCIe" fits the freq column.
    root.diskSpeed = String(raw.ssd || "").replace(/\s*PCIe$/, "").trim()
  }

  Component.onCompleted: clockProc.running = true

  // ---- hardware detection script ----
  readonly property string hwDetectScript: [
    "LANG=C",
    "{",
    "  echo cpumodel=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)",
    "  echo gpumodel=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo NA)",
    "}"
  ].join("\n")

  property Process hwDetectProc: Process {
    command: ["sh", "-c", root.hwDetectScript]
    stdout: StdioCollector {
      id: hwDetectOutput
      waitForEnd: true
      onStreamFinished: root.parseHwDetect(hwDetectOutput.text)
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
    root.cpuModel = String(raw.cpumodel || "").trim()
    root.gpuModel = String(raw.gpumodel || "").trim()
    root.cpuTjMax = detectCpuTjMax(root.cpuModel)
    root.gpuTjMax = detectGpuTjMax(root.gpuModel)
  }

  // CPU TjMax lookup by model family/name
  function detectCpuTjMax(model) {
    var m = model.toLowerCase()
    // AMD Ryzen 7000/9000 series (Zen 4/5) - 95°C TjMax
    if (m.includes("ryzen 9") || m.includes("ryzen 7") || m.includes("ryzen 5")) {
      if (m.includes("7") || m.includes("9") || m.includes("5")) return 95
    }
    // AMD Ryzen 5000 series (Zen 3) - 90°C TjMax
    if (m.includes("5600") || m.includes("5700") || m.includes("5800") || m.includes("5900") || m.includes("5950")) return 90
    // AMD Ryzen 3000 series (Zen 2) - 95°C TjMax
    if (m.includes("3") && m.includes("ryzen")) return 95
    // Intel 12th-14th gen - 100°C TjMax
    if (m.includes("i9") || m.includes("i7") || m.includes("i5") || m.includes("i3")) {
      if (m.includes("12") || m.includes("13") || m.includes("14") || m.includes("ultra")) return 100
    }
    // Intel Arrow Lake (Core Ultra 200S) - 105°C TjMax
    if (m.includes("ultra") && m.includes("2")) return 105
    // Intel older gen - 100°C TjMax
    if (m.includes("intel") || m.includes("core")) return 100
    // Default
    return 95
  }

  // GPU TjMax lookup by model
  function detectGpuTjMax(model) {
    var m = model.toLowerCase()
    // NVIDIA RTX 40/50 series - 83°C target, 90°C throttle
    if (m.includes("40") || m.includes("50")) return 83
    // NVIDIA RTX 30 series - 83°C target, 93°C throttle
    if (m.includes("30")) return 83
    // NVIDIA RTX 20 series - 84°C target, 88°C throttle
    if (m.includes("20")) return 84
    // NVIDIA GTX 16 series - 83°C target
    if (m.includes("16")) return 83
    // NVIDIA older - 85°C target
    if (m.includes("gtx") || m.includes("nvidia")) return 85
    // AMD RDNA 3 (RX 7000) - 85°C target, 110°C hotspot
    if (m.includes("7")) return 85
    // AMD RDNA 2 (RX 6000) - 80°C target, 110°C hotspot
    if (m.includes("6")) return 80
    // Default
    return 85
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

    // GPU: try Intel sysfs first, fall back to nvidia-smi
    const gidle = parseFloat(raw.gidle)
    const nvRaw = (raw.nvsmi || "").trim()
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
    } else if (nvRaw !== "NA" && nvRaw !== "") {
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
      }
      root.prevGpuIdle = -1
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
