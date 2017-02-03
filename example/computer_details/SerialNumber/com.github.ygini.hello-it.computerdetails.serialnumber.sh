#!/bin/bash
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function setTitleAction {
  serial="$(system_profiler SPHardwareDataType | grep "Serial Number" | awk -F":" '{print $2}')"
  uuid="$(system_profiler SPHardwareDataType | grep "Hardware UUID" | awk -F":" '{print $2}')"
  updateTitle "Serial: $serial"
  updateTooltip "UUID: $uuid"
  updateState "${STATE[4]}"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"
setTitleAction
exit 0
