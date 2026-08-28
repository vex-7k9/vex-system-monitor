import Quickshell
import Quickshell.Io
import QtQuick
import qs.Ui
import qs.Commons
import "Format.js" as Fmt

// Vex System Monitor — consolidated system monitor with CPU/GPU/RAM/Swap/Disk
// meters, fan monitoring, thermal envelope, and hardware autodetection.
// Features a settings GUI with gear icon in the hover card.
BarWidget {
  id: root
  moduleName: "jd.vex-system-monitor"

  // ---- settings (inline shell.json entry; fallback = manifest defaults) ----
  readonly property int updateIntervalMs: root.setting("fastPoll", true) ? 3000 : 6000
  readonly property int cpuThreshold: root.setting("cpuThreshold", 90)
  readonly property int gpuThreshold: root.setting("gpuThreshold", 95)
  readonly property int npuThreshold: root.setting("npuThreshold", 95)
  readonly property int memoryThreshold: root.setting("memoryThreshold", 95)
  readonly property int swapThreshold: root.setting("swapThreshold", 85)
  readonly property int diskThreshold: root.setting("diskThreshold", 90)

  // -- temp color scale (green -> amber -> red across the thermal envelope). --
  // Uses the detected thermal spec from the reference table (idle as the cool
  // end, peak/TjMax as the hot end), with user override via settings. On
  // unknown hardware ThermalData.js falls back to generic envelopes.
  readonly property int cpuTempCool: root.setting("cpuTempCool", Math.max(30, stats.cpuIdleTemp - 5))
  readonly property int cpuTempHot:  root.setting("cpuTempHot", stats.cpuPeakTemp)
  readonly property int gpuTempCool: root.setting("gpuTempCool", Math.max(30, stats.gpuIdleTemp - 5))
  readonly property int gpuTempHot:  root.setting("gpuTempHot", stats.gpuPeakTemp)

  // -- color mode: "theme" = Omarchy accent/urgent, "custom" = green/red gradient --
  readonly property string colorMode: root.setting("colorMode", "theme")
  readonly property bool useThemeColors: root.colorMode === "theme"

  // -- feature toggles (modular settings) --
  // Bar visibility: "show" = always in bar, "hide" = not in bar
  readonly property bool showCpu: root.meterVisible(true, "showCpu")
  readonly property bool showGpu: root.meterVisible(stats.gpuAvailable, "showGpu")
  readonly property bool showNpu: root.meterVisible(stats.npuAvailable, "showNpu")
  readonly property bool showRam: root.meterVisible(true, "showRam")
  readonly property bool showSwap: root.meterVisible(stats.swapTotalKb > 0, "showSwap")
  readonly property bool showDisk: root.meterVisible(true, "showDisk")
  readonly property bool showFans: root.meterVisible(fans.loaded && fans.fans.length > 0, "showFans")
  readonly property bool showThermals: root.meterVisible(true, "showThermals")

  // Card visibility: "show" = in hover card, "hide" = not in hover card
  readonly property bool showCpuCard: root.meterVisible(true, "showCpuCard")
  readonly property bool showGpuCard: root.meterVisible(stats.gpuAvailable, "showGpuCard")
  readonly property bool showNpuCard: root.meterVisible(stats.npuAvailable, "showNpuCard")
  readonly property bool showRamCard: root.meterVisible(true, "showRamCard")
  readonly property bool showSwapCard: root.meterVisible(stats.swapTotalKb > 0, "showSwapCard")
  readonly property bool showDiskCard: root.meterVisible(true, "showDiskCard")
  readonly property bool showFansCard: root.meterVisible(fans.loaded && fans.fans.length > 0, "showFansCard")
  readonly property bool showThermalsCard: root.meterVisible(true, "showThermalsCard")

  // Interpolate across [cool, hot]: <= cool is green(120°), >= hot is red(0°).
  function tempColor(t, cool, hot) {
    var k = Math.min(1, Math.max(0, (t - cool) / Math.max(0.001, hot - cool)))
    var h = 120 - k * 120
    var l = 55 - k * 10
    return Qt.hsla(h / 360, 0.75, l / 100, 1)
  }
  readonly property color cpuTempColor: root.tempColor(stats.cpuTempC, root.cpuTempCool, root.cpuTempHot)
  readonly property color gpuTempColor: root.tempColor(stats.gpuTempC, root.gpuTempCool, root.gpuTempHot)

  // ---- theme ----
  readonly property color normalColor: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color warnColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fam: root.bar ? root.bar.fontFamily : Style.font.family

  function warn(p, threshold) {
    return Math.round(p * 100) >= threshold
  }

  // Per-meter visibility for every show<X> setting: "Show"/"Hide" override
  // detection, "Auto" (default) shows only when the resource is available on
  // this hardware.
  function meterVisible(available, key) {
    var v = String(root.setting(key, "Auto")).toLowerCase()
    if (v === "show" || v === "true" || v === "1") return true
    if (v === "hide" || v === "false" || v === "0") return false
    return available
  }

  // ---- display mode: always text ----
  readonly property real meterFontSize: Style.font.body

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Preserve-then-set (or delete when value is empty) a single setting. Avoids
  // assigning undefined into an object literal, which is not representable in
  // the persisted JSON entry.
  function setSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    if (value === undefined || value === null || value === "") {
      if (entry[key] !== undefined) delete entry[key]
    } else entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Thermal override helpers. Overrides are optional; when unset the color
  // scale follows the detected hardware spec (auto). Clicking a value clears
  // the override back to auto.
  function tempAuto(key) {
    if (key === "cpuTempCool") return Math.max(30, svc.cpuIdleTemp - 5)
    if (key === "cpuTempHot") return svc.cpuPeakTemp
    if (key === "gpuTempCool") return Math.max(30, svc.gpuIdleTemp - 5)
    if (key === "gpuTempHot") return svc.gpuPeakTemp
    return 50
  }

  function hasTempOverride(key) {
    var v = root.settings[key]
    return v !== undefined && v !== null && String(v) !== ""
  }

  function tempSettingText(key) {
    var n = parseInt(root.setting(key, root.tempAuto(key)))
    if (isNaN(n)) return "auto \u00B0C"
    return (root.hasTempOverride(key) ? "" : "auto ") + n + "\u00B0C"
  }

  function bumpTemp(key, delta, min, max) {
    var cur = parseInt(root.setting(key, root.tempAuto(key)))
    if (isNaN(cur)) cur = root.tempAuto(key)
    root.setSetting(key, Math.max(min, Math.min(max, cur + delta)))
  }

  // ---- settings schema + migration ----
  // The plugin has shipped toggle keys for years; old shell.json entries may
  // carry stale/renamed keys (e.g. legacy "displayMode"). Every known key is
  // preserved, everything else is dropped on load, and the schema version is
  // stamped so future migrations can key off it.
  readonly property var _settingKeys: [
    "colorMode", "fastPoll", "settingsVersion",
    "showCpu", "showGpu", "showNpu", "showRam", "showSwap", "showDisk", "showFans", "showThermals",
    "showCpuCard", "showGpuCard", "showNpuCard", "showRamCard", "showSwapCard", "showDiskCard", "showFansCard", "showThermalsCard",
    "cpuThreshold", "gpuThreshold", "npuThreshold", "memoryThreshold", "swapThreshold", "diskThreshold",
    "cpuTempCool", "cpuTempHot", "gpuTempCool", "gpuTempHot", "cardBackground"
  ]

  function knownSettingKey(k) {
    return root._settingKeys.indexOf(k) >= 0
  }

  function migrateSettings() {
    var dirty = false
    var entry = { id: root.moduleName }
    for (var existing in root.settings) {
      if (existing === "id") continue
      if (root.knownSettingKey(existing)) entry[existing] = root.settings[existing]
      else dirty = true
    }
    if (root.setting("settingsVersion", 1) !== 2) {
      entry.settingsVersion = 2
      dirty = true
    }
    if (dirty) {
      root.settings = entry
      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
        root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  Component.onCompleted: {
    root.migrateSettings()
    root.cardBackgroundPath = String(root.setting("cardBackground", "") || "").trim()
  }

  // ---- hover card background ----
  // Double-clicking the card opens the same background carousel the desktop
  // uses (omarchy-menu-images / image-selector); the picked image is stored in
  // the cardBackground setting and shown behind the card content. Arrow keys
  // move the carousel and Enter applies, exactly like the desktop picker.
  property string cardBackgroundPath: ""
  readonly property string cardBgPickerScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/jd.vex-system-monitor/card-bg-picker.sh"

  readonly property string cardBackgroundName: {
    var p = root.cardBackgroundPath
    if (!p) return "none (tap to pick)"
    var base = p.replace(/\/+$/, "").split("/")
    return base.length > 0 ? base[base.length - 1] : p
  }

  function pickCardBackground() {
    if (root.cardBgPicker.running) return
    root.popupOpen = false
    root.settingsOpen = false
    root.cardBgPicker.command = ["bash", root.cardBgPickerScript, String(root.cardBackgroundPath || "")]
    root.cardBgPicker.running = true
  }

  function clearCardBackground() {
    root.cardBackgroundPath = ""
    root.setSetting("cardBackground", "")
  }

  function loadCardBackgroundSetting() {
    root.cardBackgroundPath = String(root.setting("cardBackground", "") || "").trim()
  }

  property Process cardBgPicker: Process {
    stdout: StdioCollector {
      id: cardBgOut
      waitForEnd: true
      onStreamFinished: {
        if (cardBgOut.data.length > 65536) return
        var sel = String(cardBgOut.text || "").trim()
        if (sel) {
          root.cardBackgroundPath = sel
          root.persistSettings({ cardBackground: sel })
        }
      }
    }
  }

  readonly property real memRatio: stats.memTotalKb > 0 ? stats.memUsedKb / stats.memTotalKb : 0
  readonly property real swapRatio: stats.swapTotalKb > 0 ? stats.swapUsedKb / stats.swapTotalKb : 0

  // Meter colors: theme mode uses accent/urgent, custom mode uses foreground/warn
  readonly property color cpuColor: root.useThemeColors ? (root.warn(stats.cpuUsage, root.cpuThreshold) ? Color.urgent : Color.accent) : (root.warn(stats.cpuUsage, root.cpuThreshold) ? root.warnColor : root.normalColor)
  readonly property color gpuColor: root.useThemeColors ? (root.warn(stats.gpuUsage, root.gpuThreshold) ? Color.urgent : Color.accent) : (root.warn(stats.gpuUsage, root.gpuThreshold) ? root.warnColor : root.normalColor)
  readonly property color npuColor: root.useThemeColors ? (root.warn(stats.npuUsage, root.npuThreshold) ? Color.urgent : Color.accent) : (root.warn(stats.npuUsage, root.npuThreshold) ? root.warnColor : root.normalColor)
  readonly property color memColor: root.useThemeColors ? (root.warn(root.memRatio, root.memoryThreshold) ? Color.urgent : Color.accent) : (root.warn(root.memRatio, root.memoryThreshold) ? root.warnColor : root.normalColor)
  readonly property color swapColor: root.useThemeColors ? (root.warn(root.swapRatio, root.swapThreshold) ? Color.urgent : Color.accent) : (root.warn(root.swapRatio, root.swapThreshold) ? root.warnColor : root.normalColor)
  readonly property color diskColor: root.useThemeColors ? (root.warn(stats.diskPct / 100, root.diskThreshold) ? Color.urgent : Color.accent) : (root.warn(stats.diskPct / 100, root.diskThreshold) ? root.warnColor : root.normalColor)

  // ---- data services ----
  property QtObject stats: StatsService {
    id: svc
    interval: root.updateIntervalMs
    enabled: root.visible
  }

  property QtObject fans: FanService {
    id: fans
    enabled: root.visible
  }

  onSettingsChanged: {
    svc.interval = root.setting("fastPoll", true) ? 3000 : 6000
    root.cardBackgroundPath = String(root.setting("cardBackground", "") || "").trim()
  }

  property bool settingsOpen: false

  // ---- hover open/close with grace period ----
  readonly property bool rowHovered: rowHover.hovered
  readonly property bool cardHovered: popup.containsMouse
  property bool popupOpen: false

  onRowHoveredChanged: {
    if (root.rowHovered) {
      closeTimer.stop()
      root.popupOpen = true
    } else {
      closeTimer.restart()
    }
  }
  onCardHoveredChanged: {
    if (!root.cardHovered && !root.rowHovered) closeTimer.restart()
  }

  Timer {
    id: closeTimer
    interval: 200
    onTriggered: if (!root.rowHovered && !root.cardHovered) root.popupOpen = false
  }

  implicitWidth: metersRow.implicitWidth
  implicitHeight: root.barSize

  // ---- text meters row ----
  Item {
    id: metersRow
    anchors.fill: parent
    implicitWidth: metersLayout.implicitWidth
    implicitHeight: root.barSize

    Row {
      id: metersLayout
      anchors.centerIn: parent
      spacing: 0

      Item { width: Style.spaceReal(8); height: 1 }

      MeterText {
        label: "cpu: " + Fmt.pct01(stats.cpuUsage)
        temp: stats.cpuTempC > 0 ? " " + Fmt.tempC(stats.cpuTempC) : ""
        tempColor: root.cpuTempColor
        warn: root.warn(stats.cpuUsage, root.cpuThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showCpu
      }
      MeterText {
        label: "gpu: " + Fmt.pct01(stats.gpuUsage)
        temp: stats.gpuTempC > 0 ? " " + Fmt.tempC(stats.gpuTempC) : ""
        tempColor: root.gpuTempColor
        warn: root.warn(stats.gpuUsage, root.gpuThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showGpu
      }
      MeterText {
        label: "npu: " + Fmt.pct01(stats.npuUsage)
        warn: root.warn(stats.npuUsage, root.npuThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showNpu
      }
      MeterText {
        label: "ram: " + Fmt.pct01(root.memRatio)
        warn: root.warn(root.memRatio, root.memoryThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showRam
      }
      MeterText {
        label: "swap: " + Fmt.pct01(root.swapRatio)
        warn: root.warn(root.swapRatio, root.swapThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showSwap
      }
      MeterText {
        label: "disk: " + Fmt.pct01(stats.diskPct / 100)
        warn: root.warn(stats.diskPct / 100, root.diskThreshold)
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showDisk
      }
      MeterText {
        label: "fan: " + (fans.loaded ? (fans.fans.length > 0 ? fans.fans[0].rpm + " RPM" : "no sensors") : "...")
        pct: fans.hasDeadFan ? "STOPPED" : ""
        warn: fans.hasDeadFan
        meterFontSize: root.meterFontSize
        fontFamily: root.fam
        normalColor: root.normalColor
        warnColor: root.warnColor
        barSize: root.barSize
        visible: root.showFans
      }
    }

    MouseArea {
      id: clickArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.toggleMode()
    }

    HoverHandler { id: rowHover }
  }

  // ---- hover details card ----
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen && !root.cardBgPicker.running
    contentWidth: popup.fittedContentWidth(
      Style.space(84 + 52 + 64 + 52 + 76 * 3) + Style.spacing.popupPadding * 2 + Style.space(8))
    contentHeight: popup.fittedContentHeight(details.implicitHeight)

    // Hover-card background image (optional cardBackground setting). Painted
    // behind the details column; double-click opens the desktop carousel.
    Image {
      id: cardBg
      anchors.fill: parent
      source: root.cardBackgroundPath ? Util.fileUrl(root.cardBackgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      visible: root.cardBackgroundPath !== ""
      opacity: 0.42
    }

    MouseArea {
      id: cardBgHit
      anchors.fill: parent
      // Only double-click goes to the picker; single clicks on rows above
      // still reach the gear and settings toggles because they sit on top.
      acceptedButtons: Qt.LeftButton
      onDoubleClicked: root.pickCardBackground()
    }

    Column {
      id: details
      width: parent.width
      spacing: Style.spacing.xs

      // header
      Row {
        width: parent.width
        spacing: 0
        Text { width: Style.space(84); text: "" }
        Text { width: Style.space(52); text: "Load"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        Text { width: Style.space(64); text: "Freq"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        Text { width: Style.space(52); text: "Temp"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        Text { width: Style.space(76); text: "Used"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        Text { width: Style.space(76); text: "Free"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        Text { width: Style.space(76); text: "Total"; font.family: root.fam; font.pixelSize: Style.font.caption; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
      }

      // gear icon - left aligned above CPU
      Row {
        width: parent.width
        spacing: 0
        Text {
          width: Style.space(24)
          text: "\u2699"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: root.settingsOpen ? root.normalColor : Util.alpha(root.normalColor, 0.4)
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignVCenter
          height: Style.space(24)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }
      }

      PanelSeparator { foreground: root.normalColor }

      DetailRow {
        visible: root.showCpuCard
        label: "CPU"
        labelGlyph: root.cpuGlyph
        color: root.cpuColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(stats.cpuUsage)
        freq: stats.cpuFreqMhz > 0 ? Fmt.mhz(stats.cpuFreqMhz) : "Idle"
        temp: Fmt.tempC(stats.cpuTempC)
      }
      DetailRow {
        visible: root.showGpuCard
        label: "GPU"
        labelGlyph: root.gpuGlyph
        color: root.gpuColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(stats.gpuUsage)
        freq: stats.gpuFreqMhz > 0 ? Fmt.mhz(stats.gpuFreqMhz) : "Idle"
        temp: Fmt.tempC(stats.gpuTempC)
        used: stats.gpuMemTotalMb > 0 ? (stats.gpuMemUsedMb).toFixed(0) + " MB" : "—"
        total: stats.gpuMemTotalMb > 0 ? (stats.gpuMemTotalMb).toFixed(0) + " MB" : "—"
      }
      DetailRow {
        visible: root.showNpuCard
        label: "NPU"
        labelGlyph: root.npuGlyph
        labelGlyphFont: root.faGlyphFont
        color: root.npuColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(stats.npuUsage)
        freq: stats.npuStatus === "suspended" ? "Suspended" : (stats.npuFreqMhz > 0 ? Fmt.mhz(stats.npuFreqMhz) : "Idle")
        used: stats.npuMemBytes > 0 ? (stats.npuMemBytes / 1048576).toFixed(0) + " MB" : "—"
      }
      DetailRow {
        visible: root.showRamCard
        label: "RAM"
        labelGlyph: root.memGlyph
        labelGlyphFont: root.faGlyphFont
        color: root.memColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(root.memRatio)
        freq: stats.memSpeed || "—"
        used: Fmt.gb(stats.memUsedKb)
        free: Fmt.gb(stats.memTotalKb - stats.memUsedKb)
        total: Fmt.gb(stats.memTotalKb)
      }
      DetailRow {
        visible: root.showSwapCard
        label: "Swap"
        labelGlyph: root.swapGlyph
        color: root.swapColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(root.swapRatio)
        used: Fmt.gb(stats.swapUsedKb)
        free: Fmt.gb(stats.swapTotalKb - stats.swapUsedKb)
        total: Fmt.gb(stats.swapTotalKb)
      }
      DetailRow {
        visible: root.showDiskCard
        label: "Disk"
        labelGlyph: root.diskGlyph
        color: root.diskColor
        fontFamily: root.fam
        normalColor: root.normalColor
        load: Fmt.pct01(stats.diskPct / 100)
        freq: stats.diskSpeed || "—"
        used: Fmt.gb(stats.diskUsedKb)
        free: Fmt.gb(stats.diskAvailKb)
        total: Fmt.gb(stats.diskTotalKb)
      }

      // ---- Fan speeds section ----
      PanelSeparator { foreground: root.normalColor }

      Text {
        visible: root.showFansCard
        width: parent.width
        text: fans.loaded ? (fans.fans.length > 0 ? "Fan: " + fans.fans[0].rpm + " RPM" : "Fan: no sensors") : "Fan: loading..."
        font.family: root.fam
        font.pixelSize: Style.font.bodySmall
        color: fans.hasDeadFan ? Color.urgent : root.normalColor
      }

      // ---- Hardware info section ----
      PanelSeparator { foreground: root.normalColor }

      Text {
        width: parent.width
        text: stats.cpuModel ? "CPU: " + stats.cpuModel : "CPU: detecting..."
        font.family: root.fam
        font.pixelSize: Style.font.bodySmall
        color: Util.alpha(root.normalColor, 0.6)
      }
      Text {
        width: parent.width
        text: stats.gpuModel ? "GPU: " + stats.gpuModel : "GPU: none detected"
        font.family: root.fam
        font.pixelSize: Style.font.bodySmall
        color: Util.alpha(root.normalColor, 0.6)
      }
      Text {
        width: parent.width
        text: "Thermal limits: CPU " + stats.cpuTjMax + "°C / GPU " + stats.gpuTjMax + "°C"
        font.family: root.fam
        font.pixelSize: Style.font.bodySmall
        color: Util.alpha(root.normalColor, 0.6)
      }

      // ---- thermal envelope reference (hover tooltip). ----
      PanelSeparator { foreground: root.normalColor }

      Row {
        visible: root.showThermalsCard
        width: parent.width
        spacing: 0
        Text {
          width: Style.space(84)
          text: "Thermals"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignLeft
        }
        Text {
          width: Style.space(52)
          text: "Idle"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignRight
        }
        Text {
          width: Style.space(64)
          text: "Load"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignRight
        }
        Text {
          width: Style.space(52)
          text: "Throttle"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignRight
        }
        Text {
          width: Style.space(52)
          text: "High"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignRight
        }
        Text {
          width: Style.space(52)
          text: "Now"
          font.family: root.fam
          font.pixelSize: Style.font.caption
          color: Util.alpha(root.normalColor, 0.6)
          horizontalAlignment: Text.AlignRight
        }
      }

      ThermalSpec {
        visible: root.showThermalsCard
        label: "CPU"
        idle: stats.cpuIdleTemp
        load: stats.cpuLoadTemp
        peak: stats.cpuPeakTemp
        high: stats.cpuTempHigh
        current: stats.cpuTempC
        color: root.cpuTempColor
        fontFamily: root.fam
        normalColor: root.normalColor
      }
      ThermalSpec {
        visible: root.showThermalsCard && root.showGpuCard
        label: "GPU"
        idle: stats.gpuIdleTemp
        load: stats.gpuLoadTemp
        peak: stats.gpuPeakTemp
        high: stats.gpuTempHigh
        current: stats.gpuTempC
        color: root.gpuTempColor
        fontFamily: root.fam
        normalColor: root.normalColor
      }

      // ---- Settings panel (toggled by gear icon) ----
      Column {
        visible: root.settingsOpen
        width: parent.width
        spacing: Style.spacing.xs

        PanelSeparator { foreground: root.normalColor }

        Text {
          text: "Settings"
          font.family: root.fam
          font.pixelSize: Style.font.subtitle
          font.bold: true
          color: root.normalColor
        }

        // Color mode
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            width: Style.space(84)
            text: "Colors:"
            font.family: root.fam
            font.pixelSize: Style.font.bodySmall
            color: Util.alpha(root.normalColor, 0.6)
          }
          Text {
            text: root.useThemeColors ? "Theme" : "Custom"
            font.family: root.fam
            font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.persistSettings({ colorMode: root.useThemeColors ? "custom" : "theme" })
            }
          }
        }

        // Poll speed
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text {
            width: Style.space(84)
            text: "Poll:"
            font.family: root.fam
            font.pixelSize: Style.font.bodySmall
            color: Util.alpha(root.normalColor, 0.6)
          }
          Text {
            text: root.setting("fastPoll", true) ? "3s (fast)" : "6s (slow)"
            font.family: root.fam
            font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.persistSettings({ fastPoll: !root.setting("fastPoll", true) })
            }
          }
        }

        // Column headers
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: ""; font.family: root.fam; font.pixelSize: Style.font.bodySmall }
          Text { width: Style.space(52); text: "Bar"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
          Text { width: Style.space(52); text: "Card"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6); horizontalAlignment: Text.AlignRight }
        }

        // CPU
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "CPU:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showCpu ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showCpu ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showCpu: root.showCpu ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showCpuCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showCpuCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showCpuCard: root.showCpuCard ? "Hide" : "Show" }) }
          }
        }

        // GPU
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "GPU:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showGpu ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showGpu ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showGpu: root.showGpu ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showGpuCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showGpuCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showGpuCard: root.showGpuCard ? "Hide" : "Show" }) }
          }
        }

        // NPU
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "NPU:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showNpu ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showNpu ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showNpu: root.showNpu ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showNpuCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showNpuCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showNpuCard: root.showNpuCard ? "Hide" : "Show" }) }
          }
        }

        // RAM
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "RAM:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showRam ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showRam ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showRam: root.showRam ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showRamCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showRamCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showRamCard: root.showRamCard ? "Hide" : "Show" }) }
          }
        }

        // Swap
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Swap:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showSwap ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showSwap ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showSwap: root.showSwap ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showSwapCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showSwapCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showSwapCard: root.showSwapCard ? "Hide" : "Show" }) }
          }
        }

        // Disk
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Disk:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showDisk ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showDisk ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showDisk: root.showDisk ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showDiskCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showDiskCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showDiskCard: root.showDiskCard ? "Hide" : "Show" }) }
          }
        }

        // Fans
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Fans:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showFans ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showFans ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showFans: root.showFans ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showFansCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showFansCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showFansCard: root.showFansCard ? "Hide" : "Show" }) }
          }
        }

        // Thermals
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Thermals:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showThermals ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showThermals ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showThermals: root.showThermals ? "Hide" : "Show" }) }
          }
          Text {
            width: Style.space(52); horizontalAlignment: Text.AlignRight
            text: root.showThermalsCard ? "\u2713" : "\u2717"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.showThermalsCard ? "#4CAF50" : "#F44336"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.persistSettings({ showThermalsCard: root.showThermalsCard ? "Hide" : "Show" }) }
          }
        }

        // ---- thermal color-scale overrides (auto = detected spec) ----
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "CPU cool:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text { width: Style.space(16); text: "\u2212"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("cpuTempCool", -5, 30, 60) } }
          Text {
            width: Style.space(66); horizontalAlignment: Text.AlignHCenter
            text: root.tempSettingText("cpuTempCool")
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("cpuTempCool", undefined) }
          }
          Text { width: Style.space(16); text: "+"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("cpuTempCool", 5, 30, 60) } }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "CPU hot:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text { width: Style.space(16); text: "\u2212"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("cpuTempHot", -5, 70, 110) } }
          Text {
            width: Style.space(66); horizontalAlignment: Text.AlignHCenter
            text: root.tempSettingText("cpuTempHot")
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("cpuTempHot", undefined) }
          }
          Text { width: Style.space(16); text: "+"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("cpuTempHot", 5, 70, 110) } }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "GPU cool:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text { width: Style.space(16); text: "\u2212"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("gpuTempCool", -5, 30, 60) } }
          Text {
            width: Style.space(66); horizontalAlignment: Text.AlignHCenter
            text: root.tempSettingText("gpuTempCool")
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("gpuTempCool", undefined) }
          }
          Text { width: Style.space(16); text: "+"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("gpuTempCool", 5, 30, 60) } }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "GPU hot:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text { width: Style.space(16); text: "\u2212"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("gpuTempHot", -5, 70, 110) } }
          Text {
            width: Style.space(66); horizontalAlignment: Text.AlignHCenter
            text: root.tempSettingText("gpuTempHot")
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setSetting("gpuTempHot", undefined) }
          }
          Text { width: Style.space(16); text: "+"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: root.normalColor; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bumpTemp("gpuTempHot", 5, 70, 110) } }
        }

        // Session-high temps reset
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Highs:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            text: "reset"
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: svc.resetSessionHigh() }
          }
        }

        // Hover-card background (double-click the card also opens the picker)
        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Text { width: Style.space(84); text: "Card bg:"; font.family: root.fam; font.pixelSize: Style.font.bodySmall; color: Util.alpha(root.normalColor, 0.6) }
          Text {
            width: parent.width - Style.space(84) - Style.spacing.sm
            text: root.cardBackgroundName
            elide: Text.ElideRight
            font.family: root.fam; font.pixelSize: Style.font.bodySmall
            color: root.normalColor
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) root.clearCardBackground()
                else root.pickCardBackground()
              }
            }
          }
        }
      }
    }
  }
}
