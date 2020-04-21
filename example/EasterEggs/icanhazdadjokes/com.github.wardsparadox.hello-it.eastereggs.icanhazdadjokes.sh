#!/bin/bash
# Pending Updates Script for Managed Software Center
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function displayJoke {
osascript -e "display dialog \"$(curl -s -H "User-Agent: HelloIT" -H "Accept: text/plain" https://icanhazdadjoke.com/)\" buttons {\"Haha\"} with icon POSIX file \"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ErasingIcon.icns\""
}


function onClickAction {
  displayJoke
}

function setTitleAction {
  updateTitle "Would you like to see a joke?"
  updateState "${STATE[4]}"
  updateTooltip "Brought to you by icanhazdadjoke.com"
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
