#!/bin/bash

# At each click, the script change the current controlstip
# state (full or mixed).

. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function doesControlStripIsCurrentlyFull {
	returnCode=$(defaults read com.apple.touchbar.agent PresentationModeGlobal 2>/dev/null | grep fullControlStrip | wc -l | bc)
	return $returnCode
}

function updateTitleAccordingToCurrentState {
    doesControlStripIsCurrentlyFull
    isFull=$?
	
	if [ $isFull == 0 ]
	then
		echo "hitp-title: ControlStrip"
	else
		echo "hitp-title: ControlStrip & Apps"
	fi
}

function onClickAction {
    doesControlStripIsCurrentlyFull
    isFull=$?
    
    if [ $isFull == 0 ]
	then
		defaults write com.apple.touchbar.agent PresentationModeGlobal fullControlStrip
	else
		defaults delete com.apple.touchbar.agent PresentationModeGlobal
	fi
	
	killall TouchBarAgent
    
    updateTitleAccordingToCurrentState
}

function fromCronAction {
    updateTitleAccordingToCurrentState
}

function setTitleAction {
    updateTitleAccordingToCurrentState
}

main $@

exit 0
