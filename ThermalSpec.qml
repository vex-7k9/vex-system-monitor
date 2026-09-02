import QtQuick
import qs.Commons

// One row in the hover card's "Thermals" reference: label | idle | load |
// throttle | high | current, with each temp run colored by how it falls on the
// widget's green->red gradient. "current" is the live value and "high" is the
// session-high temp, so you can compare the real temps against the spec columns
// at a glance.
Row {
  id: spec

  required property string label
  required property int idle
  required property int load
  required property int peak
  required property int high
  required property int current
  required property color color      // live color of "current"
  property string fontFamily: Style.font.family
  property color normalColor: Color.foreground

  // idle/load/throttle/high use the same interpolated gradient as the bar temp
  // text, computed over the same [cool, hot] envelope.
  function specColor(v) {
    var k = (v - spec.idle) / Math.max(0.001, spec.peak - spec.idle)
    k = Math.min(1, Math.max(0, k))
    var h = 120 - k * 120
    var l = 55 - k * 10
    return Qt.hsla(h / 360, 0.75, l / 100, 1)
  }

  readonly property real colLabel: Style.space(84)
  readonly property real colLoad: Style.space(52)
  readonly property real colFreq: Style.space(64)
  readonly property real colPeak: Style.space(52)
  readonly property real colHigh: Style.space(52)
  readonly property real colCur: Style.space(52)

  readonly property real colTotal: spec.colLabel + spec.colLoad + spec.colFreq + spec.colPeak + spec.colHigh + spec.colCur

  width: parent ? parent.width : spec.colTotal
  spacing: 0

  Text {
    width: spec.colLabel
    text: spec.label
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.color
    horizontalAlignment: Text.AlignLeft
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
  Text {
    width: spec.colLoad
    text: spec.idle + "°"
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.specColor(spec.idle)
    horizontalAlignment: Text.AlignRight
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
  Text {
    width: spec.colFreq
    text: spec.load + "°"
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.specColor(spec.load)
    horizontalAlignment: Text.AlignRight
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
  Text {
    width: spec.colPeak
    text: spec.peak + "°"
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.specColor(spec.peak)
    horizontalAlignment: Text.AlignRight
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
  Text {
    width: spec.colHigh
    text: spec.high > 0 ? spec.high + "°" : "—"
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.specColor(spec.high)
    horizontalAlignment: Text.AlignRight
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
  Text {
    width: spec.colCur
    text: spec.current + "°"
    font.family: spec.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: spec.color
    horizontalAlignment: Text.AlignRight
    renderType: Text.NativeRendering; textFormat: Text.PlainText
  }
}
