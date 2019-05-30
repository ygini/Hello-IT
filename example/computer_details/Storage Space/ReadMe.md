## Storage Space
---
##### Author: [Zack McCauley](https://www.github.com/wardsparadox)

### Description:
Displays current SMART Status in Hello-IT. Updated to use the hitp shell lib.
If under 50%: Green
If

### Preference Keys
    <dict>
        <key>functionIdentifier</key>
        <string>public.script.item</string>
        <key>settings</key>
            <dict>
                <key>script</key>
                <string>com.github.wardsparadox.hello-it.computerdetails.storagespace.sh</string>
                <key>title</key>
                <string>storagespace</string>
                <key>repeat</key>
                    <string>3600</string>
                    <key>options</key>
                    <array>
                        <string>-a</string>
                        <string>80</string>
                        <string>-w</string>
                        <string>60</string>
                    </array>
            </dict>
    </dict>
