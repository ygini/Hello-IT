#!/bin/bash
# Show Manifest name from Munki
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
 /usr/bin/open /Applications/Managed\ Software\ Center.app
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  if [ "$(defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier 2> /dev/null)" ];
  then
    # usage: updateTitle "My new title"
    # first arg only will be used as new title, don't forget quotes
    clientidentifier="$(/usr/bin/defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier)"
    updateTitle "Manifest: $clientidentifier"
    updateTooltip "Click to open Managed Software Center."
  elif [ -e "/Library/Managed Installs/manifests/$(/usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | /usr/bin/awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')" ] || [ -e "/Library/Managed Installs/manifests/$(/usr/bin/python -c "import os;print os.uname()[1]")" ];  then
    updateTitle "Using Serial/Hostname Manifest."
    updateState "${STATE[4]}"
    updateTooltip "Your device is using it's serial or hostname as a manifest. This is intended behavior."
  else
    updateTitle "No ClientIdentifier found! Contact Tech Services!"
    updateState "${STATE[1]}"
    updateTooltip "Your manifest is not found. Managed Software Center requires this! Please contact Technology Services immediatly!"
  fi

}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
