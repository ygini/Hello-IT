#!/bin/bash
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function setTitleAction {
  TotalRam="$(system_profiler SPHardwareDataType | grep "Memory:" | cut -d":" -f2)"
  updateTitle "Total RAM: $TotalRam"
  updateState "${STATE[4]}"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
