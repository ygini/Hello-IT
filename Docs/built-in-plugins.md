# Built-in plugins (1.7)

Common menu items that do not need CustomScripts. Prefer these from Configurator Mode; the scripts under `example/` remain for older releases or custom behaviour.

## System info — `public.system.info`

| Key | Values | Notes |
|-----|--------|--------|
| `kind` | `hostname`, `ip`, `wifi`, `ethernet`, `storage`, `uptime`, `memory` | Required |
| `format` | e.g. `%C`, `%C (%H)` | Hostname only |
| `interface` | BSD name e.g. `en0` | Optional for `ip` / `ethernet` |
| `mode` | `0` / `1` / `2` | IP only — hide / show unavailable / show with error when no IP |
| `warnDays` / `errorDays` | integer | Uptime defaults 7 / 14 |
| `warnPercent` / `errorPercent` | integer | Memory pressure % defaults 70 / 85 |
| `warnBelowGB` / `errorBelowGB` | integer | Storage free GB defaults 50 / 10 |
| `warnBelowSNR` / `errorBelowSNR` | integer | Wi‑Fi SNR dB defaults 25 / 15 |
| `repeat` | seconds | Refresh interval (default 60) |

Click copies the value. Ethernet hides when no active link. More detail: `example/system_info/ReadMe.md`.

## Munki — `public.munki`

| Key | Values | Notes |
|-----|--------|--------|
| `kind` | `manifest`, `pending` | ClientIdentifier / PendingUpdateCount |

Click opens Managed Software Center. Examples: `example/munki_related/`.

## Send email — `public.send.email`

| Key | Required | Description |
|---|---|---|
| `mailto` | yes | Destination address |
| `deviceURL` | no | Template with `$SERIAL` / `$UUID` / `$HOSTNAME` |
| `mailer` | no | `default` or `gmail` |
| `subject` / `body` | no | Templates (`$DEVICE_URL` and the placeholders above) |

See `example/send_email/ReadMe.md`.

## About — `public.about`

Shows Hello IT version information in the menu.
