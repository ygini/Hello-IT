# Built-in system info (`public.system.info`)

Hello IT 1.7+ can show common values without CustomScripts. Use scripts only for custom/org-specific items.

In **Configurator Mode**, pick Type → **System info**, then use the menus:

- **Info** — Hostname / IP address / Wi‑Fi / Ethernet speed / Storage / Uptime / Memory pressure
- **Format** — hostname display style
- **If offline** — what to do when there’s no IP
- **Interface** — Automatic or a specific BSD interface
- **Warn / Error thresholds** — for Uptime, Memory, Storage, and Wi‑Fi (empty = built-in defaults)
- **Notifications** — optional banners when state changes (messages pre-filled from thresholds)

## Settings (plist)

| Key | Values | Notes |
|-----|--------|--------|
| `kind` | `hostname`, `ip`, `wifi`, `ethernet`, `storage`, `uptime`, `memory` | Required |
| `format` | e.g. `%C`, `%C (%H)` | Hostname only (`%C` ComputerName, `%H` HostName, `%L` LocalHostName) |
| `interface` | BSD name e.g. `en0` | Optional for `ip` / `ethernet` |
| `mode` | `0` / `1` / `2` | IP only — hide / show unavailable / show with error state when no IP |
| `warnDays` / `errorDays` | integer | Uptime — warn/error when days since boot ≥ N (default 7 / 14) |
| `warnPercent` / `errorPercent` | integer | Memory — warn/error when pressure % ≥ N (default 70 / 85) |
| `warnBelowGB` / `errorBelowGB` | integer | Storage — warn/error when free GB &lt; N (default 50 / 10) |
| `warnBelowSNR` / `errorBelowSNR` | integer | Wi‑Fi — warn/error when SNR dB &lt; N (default 25 / 15) |
| `repeat` | seconds | Refresh interval (default 60) |

Click an item to copy its value. Ethernet hides when no active link. Storage shows free + purgeable space.

### Thresholds

| Kind | OK | Warning | Error |
|------|----|---------|-------|
| `storage` | free ≥ `warnBelowGB` (default 50) | free &lt; warn | free &lt; `errorBelowGB` (default 10) |
| `uptime` | &lt; `warnDays` (default 7) | ≥ warn | ≥ `errorDays` (default 14) |
| `memory` | pressure &lt; `warnPercent` (default 70) | ≥ warn | ≥ `errorPercent` (default 85) or kernel Critical |
| `wifi` | SNR ≥ `warnBelowSNR` (default 25) | &lt; warn | &lt; `errorBelowSNR` (default 15) |

Memory shows Activity Monitor–style pressure % (`100 − kern.memorystatus_level`). Menu colour uses those % thresholds (kernel jetsam WARN fires near ~50% and is too early to match AM’s green band). Tooltip still reports the raw kernel level.

## Example

```xml
<dict>
  <key>functionIdentifier</key>
  <string>public.system.info</string>
  <key>settings</key>
  <dict>
    <key>kind</key>
    <string>uptime</string>
    <key>warnDays</key>
    <integer>7</integer>
    <key>errorDays</key>
    <integer>14</integer>
    <key>repeat</key>
    <integer>60</integer>
  </dict>
</dict>
```
