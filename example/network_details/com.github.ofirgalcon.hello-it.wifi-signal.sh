#!/bin/bash

# Display wifi SNR as title

. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

function getWifiSNR {
	wifi=$(/System/Library/PrivateFrameworks/Apple*.framework/Versions/Current/Resources/airport -I)
    signal=$(echo "$wifi" | grep CtlRSSI | sed -e 's/^.*://g')
    noise=$(echo "$wifi" | grep CtlNoise | sed -e 's/^.*://g')
    SNR=$((signal-noise))

    echo "$SNR dBm"
}

function updateTitleWithArgs {
    title=$(getWifiSNR)
    updateTitle "WiFi SNR: $title"
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
