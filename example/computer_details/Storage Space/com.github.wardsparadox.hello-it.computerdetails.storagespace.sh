#!/bin/bash
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  storagecmd="$(df -H / | grep "/" | awk '{print $3" / "$2 " Used,",$5 " used"}')"
  total="$(df / | grep "/" | awk '{print $2}' | sed 's/G//')"
  used="$(df / | grep "/" | awk '{print $3}' | sed 's/G//')"
  percentused="$(printf "%.0f\n" "$(bc -l <<< "( $used / $total) * 100")")"


  if [[ "$percentused" -gt 90 ]]; then
    updateState "${STATE[2]}"
  elif [[ "$percentused" -lt 70 ]]; then
    updateState "${STATE[0]}"
  else
    updateState "${STATE[1]}"
  fi
  updateTitle "Storage: $storagecmd"
  setEnabled YES
}


### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
