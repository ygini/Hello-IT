#!/bin/bash

# At each click, the script change the current desktop
# state (to hide or no icons on the desktop).
# 
# This script display a checkmark on Hello IT menu 
# when the desktop is hidden. The script don't provide
# any built-in title. So use the Hello IT title setting
# to set something coherent for your main language.
# Something like "Presenter Mode" or "Hide Desktop".

. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function doesDesktopIsCurrentlyHidden {
	returnCode=$(defaults read com.apple.finder CreateDesktop | grep -i false | wc -l | bc)
	return $returnCode
}

function updateTitleAccordingToCurrentState {
    doesDesktopIsCurrentlyHidden
    isHidden=$?
	
	if [ $isHidden == 0 ]
	then
		echo "hitp-checked: NO"
	else
		echo "hitp-checked: YES"
	fi
}

function onClickAction {
    doesDesktopIsCurrentlyHidden
    isHidden=$?
    
    if [ $isHidden == 1 ]
	then
		defaults write com.apple.finder CreateDesktop true
	else
		defaults write com.apple.finder CreateDesktop false
	fi
	
	killall Finder
    
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
