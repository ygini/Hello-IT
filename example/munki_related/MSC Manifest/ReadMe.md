##Munki Manifest Name
---
##### Author: [Zack McCauley](https://www.github.com/WardsParadox)

###Description:
Provides user with name of manifest currently in use by the computer. Useful for my district. - Zack McCauley

### Preference Keys to add:
    <dict>
      <key>functionIdentifier</key>
      <string>public.script.item</string>
      <key>settings</key>
      <dict>
        <key>script</key>
        <string>com.github.ygini.hello-it.munki.manifestname.sh</string>
        <key>title</key>
        <string>manifestname</string>
      </dict>
    </dict>
