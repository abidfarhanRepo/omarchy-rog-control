import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// ROG control — an Omarchy bar panel for ASUS ROG / TUF laptops.
//
//   Bar    : the ROG wordmark. Clicking it opens the panel and changes
//            nothing on its own.
//   Panel  : live sensors, plus a dropdown each for power profile, battery
//            charge limit, and keyboard backlight.
//
// Nothing about this machine is hardcoded. Model, CPU and discrete GPU are
// read from DMI and the PCI modalias; every section hides itself when the
// hardware does not expose the corresponding sysfs attribute, so the same
// plugin degrades cleanly from a G14 to a TUF without a dGPU.
//
// All reads go through bin/rog-status and all writes through bin/rog-set,
// both resolved relative to this file so the plugin is self-contained.

Panel {
  id: root
  moduleName: "armnt.rog-control"
  ipcTarget: "armnt.rog-control"

  // Absolute path to this plugin's directory, so the bundled helpers can be
  // invoked without requiring anything on $PATH.
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")

  // Raw key/value state from bin/rog-status.
  property var state: ({})
  property bool cursorActive: false
  property int cursorIndex: 0

  // ---- capability gates ----------------------------------------------------
  readonly property bool hasProfiles: String(root.state.profile_choices || "") !== ""
  readonly property bool hasCap: root.state.cap !== undefined
  readonly property bool hasKbd: root.state.kbd !== undefined
  readonly property bool hasDgpu: root.state.dgpu !== undefined

  readonly property var controls: {
    var out = []
    if (root.hasProfiles) out.push("profile")
    if (root.hasCap) out.push("cap")
    if (root.hasKbd) out.push("kbd")
    return out
  }
  function controlAt(i) { return i >= 0 && i < root.controls.length ? root.controls[i] : "" }

  // ---- identity ------------------------------------------------------------
  readonly property string machineName: {
    var n = String(root.state.family || root.state.model || "")
    // The wordmark already says ROG; repeating it in the title is noise.
    n = n.replace(/^ROG\s+/, "").trim()
    return n !== "" ? n : "ROG control"
  }
  readonly property string hardwareLine: {
    var bits = []
    if (root.state.cpu_model !== undefined) bits.push(root.state.cpu_model)
    if (root.state.dgpu_model !== undefined) bits.push(root.state.dgpu_model)
    return bits.join("  ·  ")
  }

  // ---- options -------------------------------------------------------------
  readonly property var profileOptions: {
    var raw = String(root.state.profile_choices || "").split(" ")
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var v = raw[i].trim()
      if (v !== "") out.push({ value: v, label: root.profileLabel(v) })
    }
    return out
  }

  readonly property var capOptions: [
    { value: "60", label: "60%  ·  long-term storage" },
    { value: "80", label: "80%  ·  daily use (recommended)" },
    { value: "100", label: "100%  ·  full capacity" }
  ]

  // Four discrete hardware levels get a dropdown rather than a slider — a
  // slider over four steps is fiddly to land on the value you want.
  readonly property var kbdOptions: {
    var names = ["Off", "Low", "Medium", "High"]
    var out = []
    for (var i = 0; i <= root.kbdMax; i++) {
      out.push({ value: String(i), label: i < names.length ? names[i] : ("Level " + i) })
    }
    return out
  }

  function profileLabel(name) {
    // ASUS names on the left, so the panel reads the way the laptop is
    // badged; the power-profiles-daemon name is what actually gets set.
    if (name === "power-saver") return "Silent"
    if (name === "balanced") return "Balanced"
    if (name === "performance") return "Turbo"
    return name
  }

  readonly property string activeProfile: String(root.state.profile || "")
  readonly property string activeCap: String(root.state.cap || "")
  readonly property int kbdLevel: parseInt(root.state.kbd || "0", 10) || 0
  readonly property int kbdMax: Math.max(1, parseInt(root.state.kbd_max || "3", 10) || 3)

  // PanelHero renders `detail` as a pill on the title row and elides the title
  // to make room, so this stays short.
  readonly property string heroDetail: root.activeProfile !== ""
    ? root.profileLabel(root.activeProfile).toUpperCase()
    : ""

  readonly property string heroMeta: {
    var bits = []
    if (root.state.battery !== undefined) {
      bits.push(root.state.battery + "%" + (root.hasCap ? " / " + root.activeCap + " cap" : ""))
    }
    if (root.state.cpu_temp !== undefined) bits.push("CPU " + root.state.cpu_temp + "°C")
    if (root.state.fan_cpu_fan !== undefined) bits.push(root.state.fan_cpu_fan + " rpm")
    return bits.length > 0 ? bits.join("  ·  ") : "Reading sensors…"
  }

  function temp(key) { return root.state[key] !== undefined ? root.state[key] + "°C" : "—" }
  function rpm(key) { return root.state[key] !== undefined ? root.state[key] + " rpm" : "—" }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var idx = lines[i].indexOf("\t")
      if (idx <= 0) continue
      next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
    }
    // Keep the last good snapshot if a poll returns nothing — sensors go
    // briefly unreadable around AC transitions and suspend/resume, and the
    // panel must not blank out for that.
    if (Object.keys(next).length === 0) return
    root.state = next
  }

  function apply(kind, value) {
    if (setProc.running) return
    setProc.command = [root.pluginDir + "/bin/rog-set", kind, String(value)]
    setProc.running = true
  }

  onOpenedChanged: if (root.opened) { root.refresh(); root.cursorActive = false }

  Process {
    id: statusProc
    command: [root.pluginDir + "/bin/rog-status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: setProc
    onExited: settleTimer.restart()
  }

  // A write reaches sysfs before the daemon has finished reacting; re-read
  // shortly after so the control snaps to the value the hardware accepted
  // rather than the one we asked for.
  Timer { id: settleTimer; interval: 700; onTriggered: root.refresh() }
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The wordmark is a lockup, not a glyph — give it the width of two icon
    // slots so it is not squeezed into a square.
    slotSize: Style.bar.iconSlot * 2
    active: root.opened
    tooltipText: {
      var t = root.machineName
      if (root.hardwareLine !== "") t += "\n" + root.hardwareLine
      if (root.activeProfile !== "") t += "\n" + root.profileLabel(root.activeProfile)
        + (root.hasCap ? "  ·  charge limit " + root.activeCap + "%" : "")
      return t
    }
    onPressed: root.toggle()

    iconComponent: Component {
      RogMark {
        anchors.centerIn: parent
        markHeight: Style.bar.iconFont * 0.78
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a dropdown popup owns the keys, freeze the panel cursor so j/k
      // does not drive both at once.
      blocked: profileDropdown.popupOpen || capDropdown.popupOpen || kbdDropdown.popupOpen

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        var n = root.controls.length
        if (dy !== 0 && n > 0) root.cursorIndex = (root.cursorIndex + dy + n) % n
      }
      onActivateRequested: {
        if (!root.cursorActive) { root.cursorActive = true; return }
        var c = root.controlAt(root.cursorIndex)
        if (c === "profile") profileDropdown.toggle()
        else if (c === "cap") capDropdown.toggle()
        else if (c === "kbd") kbdDropdown.toggle()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        PanelHero {
          width: parent.width
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          title: root.machineName
          meta: root.heroMeta
          detail: root.heroDetail
          iconComponent: Component {
            RogMark {
              markHeight: Style.font.display
              color: root.bar.foreground
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.hardwareLine
          visible: text !== ""
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Sensors ----------
        Row {
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "CPU"
              value: root.temp("cpu_temp")
              visible: root.state.cpu_temp !== undefined
            }
            InfoPair {
              label: "iGPU"
              value: root.temp("igpu_temp")
              visible: root.state.igpu_temp !== undefined
            }
            InfoPair {
              label: "dGPU"
              visible: root.hasDgpu
              value: root.state.dgpu === "active"
                ? (root.state.dgpu_temp !== undefined ? root.state.dgpu_temp + "°C" : "on")
                : "asleep"
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "CPU fan"
              value: root.rpm("fan_cpu_fan")
              visible: root.state.fan_cpu_fan !== undefined
            }
            InfoPair {
              label: "GPU fan"
              value: root.rpm("fan_gpu_fan")
              visible: root.state.fan_gpu_fan !== undefined
            }
            InfoPair {
              label: "Battery"
              visible: root.state.battery !== undefined
              value: root.state.battery + "%  " + String(root.state.battery_state || "").toLowerCase()
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Performance ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.hasProfiles

          PanelSectionHeader {
            text: "PERFORMANCE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Dropdown {
            id: profileDropdown
            width: parent.width
            label: "Power profile"
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            options: root.profileOptions
            value: root.activeProfile
            hasCursor: root.cursorActive && root.controlAt(root.cursorIndex) === "profile"
            onHovered: function(h) {
              if (h) { root.cursorActive = true; root.cursorIndex = root.controls.indexOf("profile") }
            }
            onChanged: function(v) { root.apply("profile", v) }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.state.acpi_profile !== undefined ? "ASUS thermal mode: " + root.state.acpi_profile : ""
            visible: text !== ""
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Battery ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.hasCap

          PanelSectionHeader {
            text: "BATTERY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Dropdown {
            id: capDropdown
            width: parent.width
            label: "Charge limit"
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            options: root.capOptions
            value: root.activeCap
            hasCursor: root.cursorActive && root.controlAt(root.cursorIndex) === "cap"
            onHovered: function(h) {
              if (h) { root.cursorActive = true; root.cursorIndex = root.controls.indexOf("cap") }
            }
            onChanged: function(v) { root.apply("cap", v) }
          }
        }

        // ---------- Keyboard ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.hasKbd

          PanelSectionHeader {
            text: "KEYBOARD BACKLIGHT"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Dropdown {
            id: kbdDropdown
            width: parent.width
            label: "Brightness"
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            options: root.kbdOptions
            value: String(root.kbdLevel)
            hasCursor: root.cursorActive && root.controlAt(root.cursorIndex) === "kbd"
            onHovered: function(h) {
              if (h) { root.cursorActive = true; root.cursorIndex = root.controls.indexOf("kbd") }
            }
            onChanged: function(v) { root.apply("kbd", v) }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Physical keys: Fn + Up / Fn + Down"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
