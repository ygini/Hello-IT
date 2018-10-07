#!/bin/bash
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  osversion="$(sw_vers | grep "ProductVersion" | awk '{print $2}')"
  buildversion="$(sw_vers | grep "Build" | awk '{print $2}')"
  updateTitle "macOS Version: $osversion"
  updateState "${STATE[4]}"
  updateTooltip "macOS Build: $buildversion"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
