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
        <key>path</key>
        <string>/Library/Application Support/com.github.ygini.hello-it/CustomScripts/com.github.ygini.hello-it.pendingmscupdates.sh</string>
        <key>periodic-run</key>
        <integer>360</integer>
        <key>title</key>
        <string>pendingupdatescount</string>
      </dict>
    </dict>
