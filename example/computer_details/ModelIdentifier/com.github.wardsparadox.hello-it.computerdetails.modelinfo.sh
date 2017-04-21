#!/bin/bash
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function setTitleAction {
  Model="$(system_profiler SPHardwareDataType | grep -i "Model Name" | awk -F":" '{print $2}')"
  ModelID="$(system_profiler SPHardwareDataType | grep -i "Identifier" | awk -F":" '{print $2}')"
  updateTitle "Model: $Model"
  updateState "${STATE[4]}"
  updateTooltip "Model ID: $ModelID"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
