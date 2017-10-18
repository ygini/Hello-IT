#!/bin/bash

# Display computer IP address as title
# With no option, the script detect the main
# interface used to reach 8.8.8.8
#
# You can specify source interface with -i option
#
# You can specify the behavior if no IP
# are found with -m option:
# 0: show IP if available, hide if not
# 1: show IP if available, specify if not, no $STATE
# 2: show IP if available, specify if not, use $STATE

. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

mode=0
mainBSDInterface=$(route -n get 8.8.8.8 | grep "interface: " | awk -F ": " '{print $2}')

function handleOptions {
	while getopts "m:i:" o; do
		case "${o}" in
			m)
				mode=${OPTARG}
				;;
			i)
				mainBSDInterface=${OPTARG}
				;;
		esac
	done
}
	
function handleStateUpdate {
	mode=$1
	requestedState=$2

	if [ $mode -eq 0 ]
	then
		if [ "$requestedState" == ${STATE[0]} ]
		then
			setHidden NO
		else
			setHidden YES
		fi
	else
		setHidden NO
		if [ $mode -eq 1 ]
		then
			updateState ${STATE[4]}
		else
			updateState $requestedState
		fi
	fi
}

function getIP {
	ifconfig "$mainBSDInterface" | grep "inet " | sed "s/.*inet \([0-9.]*\).*/\1/" | head -n1
}

function updateTitleWithArgs {
    ipAddress=$(getIP "$@")
    
	if [ -z "$ipAddress" ]
	then
		updateTitle "No IP Address"
		if [[ "$HELLO_IT_NETWORK_STATE" == "1" ]]
		then
			handleStateUpdate $mode ${STATE[2]}
			updateTooltip "Please, check your Ethernet or WiFi connection"
		else
			handleStateUpdate $mode ${STATE[3]}
			updateTooltip "No network connection available"
		fi
	else
		updateTitle "Local IP: $ipAddress"
		handleStateUpdate $mode ${STATE[0]}
    	updateTooltip "Having an IP address doesn't mean you've Internet access"
	fi

}

function onClickAction {
    updateTitleWithArgs "$@"
    getIP "$@" | pbcopy
}

function fromCronAction {
    updateTitleWithArgs "$@"
}

function setTitleAction {
    updateTitleWithArgs "$@"
}

main "$@"

exit 0
