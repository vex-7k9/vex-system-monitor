# Vex System Monitor

A consolidated system monitor for [Omarchy](https://omarchy.org/) that merges the best features from multiple community plugins into a single, configurable bar widget.

## Features

- **Hardware autodetection** — CPU/GPU models and thermal limits detected automatically
- **Dynamic temperature thresholds** — Sets correct TjMax based on your hardware
- **CPU/GPU/NPU/RAM/Swap/Disk meters** — live usage percentages in the bar
- **Temperature monitoring** — CPU and GPU temps with color-coded thermal envelope
- **Fan monitoring** — live RPM via lm_sensors
- **Modular settings** — toggle each meter on/off for bar and hover card separately
- **Theme integration** — uses Omarchy's accent/urgent colors or custom green/red gradient
- **Settings GUI** — gear icon in hover card for quick configuration
- **Card background** — double-click the hover card for the desktop background carousel (arrow keys + Enter), stored per-card; right-click the card (or its settings value) to clear back to the default

## Installation

```bash
omarchy plugin add https://github.com/vex-7k9/vex-system-monitor.git
```

## Configuration

Click the gear icon (⚙) in the hover card to access settings:

- **Colors**: Theme (Omarchy accent/urgent) or Custom (green/red gradient)
- **Bar/Card toggles**: Choose which meters appear in the bar vs hover card only
- **Thresholds**: CPU/GPU/RAM/Swap/Disk warning levels
- **Temperature gradient**: Auto-detected from hardware, or manually override
- **Card bg**: Set the current background; left-click opens the desktop background carousel (arrow keys + Enter), right-click clears back to the default card

**Hardware Detection**: On load the plugin detects your CPU and GPU models and looks up real-world thermal envelopes (idle/load/throttle/TjMax) from a built-in reference table covering most common CPU/GPU combos. Hover over the widget to see the detected hardware, its thermal limits, and the Idle/Load/Throttle/High/Now reference — High tracks the session max temp. If your hardware isn't in the table, sensible averaged defaults are used so the color gradient still works.

## Hardware Temperature Reference

Use these ranges to set your thermal gradient (cool/hot) values:

| State | CPU | GPU | What It Means |
|-------|-----|-----|---------------|
| Idle | 30–50°C | 30–45°C | Normal — fans may stop on GPUs |
| Light work | 50–65°C | 45–60°C | Browsing, office work |
| Gaming | 65–85°C | 60–80°C | Normal under load |
| Heavy load | 85–95°C | 80–87°C | Check airflow |
| Throttle | 95–100°C+ | 88–95°C+ | Chip slows itself to survive |

**Default gradient values**: Auto-derived from the detected hardware's thermal spec (idle→peak TjMax); falls back to an averaged envelope when hardware is unknown. Manual overrides are still available via the settings.

**AMD Ryzen**: TjMax is 95°C (including 9800X3D/9950X3D)
**Intel**: TjMax is 100–105°C (Arrow Lake: 105°C)
**NVIDIA GPUs**: Designed to sit near 83–87°C at fan curve equilibrium

## Credits

This plugin consolidates features from these excellent community projects:

| Plugin | Author | License | Link |
|--------|--------|---------|------|
| [omarchy-system-monitor](https://github.com/tslove923/omarchy-system-monitor) | tslove923 | MIT | [GitHub](https://github.com/tslove923/omarchy-system-monitor) |
| [omarchy-plus-fan-monitor](https://github.com/ol4vr/omarchy-plus-fan-monitor) | ol4vr (forked from elynch303) | MIT | [GitHub](https://github.com/ol4vr/omarchy-plus-fan-monitor) |
| [omarchy-temperature-plugin](https://github.com/Rizmi/omarchy-temperature-plugin) | Rizmi | MIT | [GitHub](https://github.com/Rizmi/omarchy-temperature-plugin) |

### What Changed

- Merged three separate plugins into one unified widget
- Added modular bar/card visibility toggles per meter
- Added theme color integration (Omarchy accent/urgent)
- Added settings GUI with gear icon in hover card
- Removed unused Icons/Text mode (simplified to text only)

## License

MIT License — see individual credits above for original authors.

## Requirements

- [Omarchy](https://omarchy.org/) with QuickShell
- lm-sensors (for fan monitoring)
- nvidia-smi (for NVIDIA GPU monitoring)
