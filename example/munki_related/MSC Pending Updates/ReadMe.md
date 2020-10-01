## Pending Munki Updates
---
##### Author: [Zack McCauley](https://www.github.com/WardsParadox)

### Description:
Provides user feedback as to how many Managed Software Center updates are available. If any are available, it displays a warning. You could of course change this.

### Preference Keys to add:
    <dict>
      <key>functionIdentifier</key>
      <string>public.script.item</string>
      <key>settings</key>
      <dict>
        <key>script</key>
        <string>com.github.wardsparadox.hello-it.munki.pendingmscupdates.sh</string>
        <key>repeat</key>
        <integer>360</integer>
        <key>title</key>
        <string>pendingupdatescount</string>
      </dict>
    </dict>
