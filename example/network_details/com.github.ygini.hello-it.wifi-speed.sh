#!/bin/bash

# Display Wifi Tx rate as title

. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function getWifiSpeed {
    speed=$(/System/Library/PrivateFrameworks/Apple*.framework/Versions/Current/Resources/airport -I | grep lastTx | sed -e 's/^.*://g' )    
    echo "$speed Mbps"
}

function updateTitleWithArgs {
    title=$(getWifiSpeed)
    updateTitle "WiFi speed: $title"
}

function onClickAction {
    updateTitleWithArgs "$@"
    getHostname | pbcopy
}

function fromCronAction {
    updateTitleWithArgs "$@"
}

function setTitleAction {
    updateTitleWithArgs "$@"
}

function onNetworkAction {
	updateTitleWithArgs "$@"
}

main "$@"

exit 0
