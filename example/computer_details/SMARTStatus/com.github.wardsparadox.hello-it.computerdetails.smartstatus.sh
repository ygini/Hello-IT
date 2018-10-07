#!/bin/bash
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  smartstatus="$(diskutil info disk0 | awk '/SMART Status/ {print $3,$4}')"
  if [[ "$smartstatus" = "Verified " ]]; then
    updateState "${STATE[0]}"
  elif [[ "$smartstatus" = "Not Supported" ]]; then
    updateState "${STATE[4]}"
  else
    updateState "${STATE[2]}"
  fi
  updateTitle "SMART Status: $smartstatus"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
