# Send email

Built-in type `public.send.email` opens a prefilled message in the default mailer (`mailto:`) or Gmail compose.

## Settings

| Key | Required | Description |
|---|---|---|
| `mailto` | yes | Destination address |
| `deviceURL` | no | Template URL with `$SERIAL` / `$UUID` / `$HOSTNAME` |
| `mailer` | no | `default` (system mailer) or `gmail` |
| `subject` | no | Subject template (same placeholders + `$DEVICE_URL`) |
| `body` | no | Body template. If omitted (or present without `$DEVICE_URL`) and `deviceURL` is set, a protected block is appended: blank lines, “Please do not edit the line below”, a rule, then the resolved device URL |

## Example

```xml
<dict>
  <key>functionIdentifier</key>
  <string>public.send.email</string>
  <key>settings</key>
  <dict>
    <key>title</key>
    <string>Email IT about this Mac</string>
    <key>mailto</key>
    <string>helpdesk@example.com</string>
    <key>deviceURL</key>
    <string>https://report.example.com/device?$UUID</string>
    <key>mailer</key>
    <string>gmail</string>
    <key>subject</key>
    <string>Help — $SERIAL</string>
    <key>body</key>
    <string>Please help with this Mac.

Device: $DEVICE_URL
Hostname: $HOSTNAME
Serial: $SERIAL</string>
  </dict>
</dict>
```
