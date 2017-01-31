#!/bin/bash
# Show Manifest name from Munki
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
 /usr/bin/open /Applications/Managed\ Software\ Center.app
}

function setTitleAction {
  if [ "$(defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier 2> /dev/null)" ];
  then
    # usage: updateTitle "My new title"
    # first arg only will be used as new title, don't forget quotes
    clientidentifier="$(/usr/bin/defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier)"
    updateTitle "Manifest: $clientidentifier"
    updateTooltip "Click to open Managed Software Center."
  else
    updateTitle "No ClientIdentifier found! Contact Tech Services!"
    updateState "${STATE[1]}"
    updateTooltip "Your manifest is not found. Managed Software Center requires this! Please contact Technology Services immediatly!"
  fi

}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
