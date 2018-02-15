#!/bin/bash

. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"


function onClickAction {
    setTitleAction "$@"
}

function fromCronAction {
    setTitleAction "$@"
}

function setTitleAction {
  macaddr="$(python -c "from uuid import getnode; print hex(getnode())[2:]")"
  updateTitle "MAC Address: $macaddr"
  updateTooltip "MAC Address is the identifier to the network"
}

main "$@"

exit 0
