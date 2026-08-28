# Vex System Monitor

A consolidated system monitor for [Omarchy](https://omarchy.org/) that merges the best features from multiple community plugins into a single, configurable bar widget.

## Features

- **CPU/GPU/NPU/RAM/Swap/Disk meters** — live usage percentages in the bar
- **Temperature monitoring** — CPU and GPU temps with color-coded thermal envelope
- **Fan monitoring** — live RPM via lm_sensors
- **Hardware autodetection** — GPU/NPU/fans auto-hide when unavailable
- **Modular settings** — toggle each meter on/off for bar and hover card separately
- **Theme integration** — uses Omarchy's accent/urgent colors or custom green/red gradient
- **Settings GUI** — gear icon in hover card for quick configuration

## Installation

```bash
omarchy plugin add https://github.com/vex-7k9/vex-system-monitor.git
```

## Configuration

Click the gear icon (⚙) in the hover card to access settings:

- **Colors**: Theme (Omarchy accent/urgent) or Custom (green/red gradient)
- **Bar/Card toggles**: Choose which meters appear in the bar vs hover card only
- **Thresholds**: CPU/GPU/RAM/Swap/Disk warning levels

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
