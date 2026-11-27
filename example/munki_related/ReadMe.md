## Munki Related Hello-IT Scripts
---
##### Author: [Zack McCauley](https://www.github.com/WardsParadox)

### Description

**Hello IT 1.7+:** Prefer the built-in Type → **Munki** in Configurator Mode (`public.munki`, kinds `manifest` / `pending`). The sample `com.github.ygini.Hello-IT.munkirelated.plist` uses those built-ins.

The scripts under this folder remain as examples / for older releases.

### Built-in sample (1.7+)

```xml
<dict>
  <key>functionIdentifier</key>
  <string>public.munki</string>
  <key>settings</key>
  <dict>
    <key>kind</key>
    <string>manifest</string>
    <key>title</key>
    <string>MSC Manifest</string>
  </dict>
</dict>
```

```xml
<dict>
  <key>functionIdentifier</key>
  <string>public.munki</string>
  <key>settings</key>
  <dict>
    <key>kind</key>
    <string>pending</string>
    <key>title</key>
    <string>Pending MSC Updates</string>
    <key>repeat</key>
    <integer>360</integer>
  </dict>
</dict>
```
