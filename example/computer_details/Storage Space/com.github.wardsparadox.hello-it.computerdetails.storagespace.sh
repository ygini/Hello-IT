#!/bin/bash
. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function handleOptions {
  unset opt
  alertpercentage=90; # set defaults to mitigate migration
  warningpercentage=70; # set defaults to mitigate migration
  while getopts "a:w:" opt; do
    case "${opt}" in
      a)
        alertpercentage=${OPTARG}
        ;;
      w)
        warningpercentage=${OPTARG}
        ;;
      *)
        alertpercentage=90;
        warningpercentage=70;
        ;;
    esac
  done
}

function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
   setTitleAction "$@"
}

function setTitleAction {
  diskinfo="$(diskutil info /dev/disk1s1)"
  total="$(awk '/Volume Total Space/ { print $4 }' <<<"$diskinfo")"
  used="$(awk '/Volume Used Space/ { print $4 }' <<<"$diskinfo")"
  percentused="$(printf "%.0f\n" "$(bc -l <<< "( $used / $total) * 100")")"
  storage="$used GB / $total GB Used, $percentused % used"
  handleOptions

  if [[ "$percentused" -gt $alertpercentage ]]; then
    updateState "${STATE[2]}"
  elif [[ "$percentused" -lt $warningpercentage ]]; then
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
