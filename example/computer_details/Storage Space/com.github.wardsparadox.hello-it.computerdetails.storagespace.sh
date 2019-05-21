#!/bin/bash
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  total="$(diskutil info /dev/disk1s1 |  awk '/Volume Total Space/ { print $4 }')"
  used="$(diskutil info /dev/disk1s1 |  awk '/Volume Used Space/ { print $4 }')"
  percentused="$(printf "%.0f\n" "$(bc -l <<< "( $used / $total) * 100")")"
  storage="$used GB / $total GB Used, $percentused % used"


  if [[ "$percentused" -gt 90 ]]; then
    updateState "${STATE[2]}"
  elif [[ "$percentused" -lt 70 ]]; then
    updateState "${STATE[0]}"
  else
    updateState "${STATE[1]}"
  fi
  updateTitle "Storage: $storage"
  setEnabled YES
}


### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"

exit 0
