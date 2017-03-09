#!/bin/bash

# To perform a sleep action
# Requires "password after sleep or screen saver begins" to be set in Security preferences

. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

function goToSleep {
	osascript -e 'tell application "Finder" to sleep'
}

function onClickAction {
    goToSleep $@
}

main $@

exit 0
