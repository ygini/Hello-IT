#!/bin/bash

### Following function can be overrided by scripts ###

# override this function if you need to parse your options array before everything else
function handleOptions {
:
}

# override this function to specify what to do when the user clic on your menu item
function onClickAction {
:
}

# override this function to specify what to do when the network change
function onNetworkAction {
:
}

# override this function to specify what to do when the script is on a periodic run
function fromCronAction {
:
}

# override this function to specify the item title when UI is loaded (optional, use it
# when your title is always dynamic and can't have a default value). For default value
# use the title key in Hello IT's settings.
function setTitleAction {
:
}

### Following function can be called but must not be overrided by scripts ###

STATE=("ok" "warning" "error" "unavailable" "none")

# usage: updateState ${STATE[0]}
# supported states are managed by the STATE array
# ${STATE[0]} --> OK (Green light)
# ${STATE[1]} --> Warning (Orange light)
# ${STATE[2]} --> Error (Red light)
# ${STATE[3]} --> Unavailable (Empty circle)
# ${STATE[4]} --> No state to display (Nothing at all)
function updateState {
    echo "hitp-state: $1"
}

# usage: updateTitle "My new title"
# first arg only will be used as new title, don't forget quotes
function updateTitle {
    echo "hitp-title: $1"
}

# usage: setEnabled "YES"
# supported values are YES or NO as string
function setEnabled {
    echo "hitp-enabled: $1"
}

# usage: setHidden "YES"
# supported values are YES or NO as string 
function setHidden {
    echo "hitp-hidden: $1"
}

# usage: updateTooltip "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function updateTooltip {
    echo "hitp-tooltip: $1"
}

# usage: emergencyLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function emergencyLog {
    echo "hitp-log-emerg: $1"
}

# usage: alertLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function alertLog {
    echo "hitp-log-alert: $1"
}

# usage: criticalLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function criticalLog {
    echo "hitp-log-crit: $1"
}


# usage: errorLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function errorLog {
    echo "hitp-log-err: $1"
}

# usage: warningLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function warningLog {
    echo "hitp-log-warning: $1"
}

# usage: noticeLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function noticeLog {
    echo "hitp-log-notice: $1"
}

# usage: infoLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function infoLog {
    echo "hitp-log-info: $1"
}

# usage: debugLog "This aren't the droids you're looking for"
# first arg only will be used as new title, don't forget quotes
function debugLog {
    echo "hitp-log-debug: $1"
}

### Following function must not be called or overrided by scripts ###

# this function contain all code needed to understand the current context from Hello IT
# and will call Action functions previously defined. Just override the previous function
# and call the main function at the end of your script and you will be set.
function main {
	run_option=$1

	if [ "$HELLO_IT_OPTIONS_AVAILABLE" == "yes" ]
	then
		options=("$HELLO_IT_OPTIONS")
        handleOptions $options
	fi
	
	case "$run_option" in
		run)
			onClickAction $options
		;;
		periodic-run)
			fromCronAction $options
		;;
		title)
			setTitleAction $options
		;;
		network)
			onNetworkAction $options
		;;
		*)
            echo "Usage: $0 {run|periodic-run|network|title}"
            echo "$run_option not recognized"
            exit 1
        ;;
	esac
}
