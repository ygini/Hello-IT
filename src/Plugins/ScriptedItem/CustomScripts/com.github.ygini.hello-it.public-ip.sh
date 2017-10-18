#!/bin/bash

# Display Public IP address as title
# With no option, the script detect the public
# address using https://ip.abelionni.com/script/
#
# You can specify the test URL using -u
#
# You can specify the behavior if no IP
# are found with -m option:
# 0: show IP if available, hide if not
# 1: show IP if available, specify if not, no $STATE
# 2: show IP if available, specify if not, use $STATE

. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

mode=0
public_ip_url="https://ip.abelionni.com/script/"

function handleOptions {
    while getopts "m:u:" o; do
        case "${o}" in
            m)
                mode=${OPTARG}
                ;;
            u)
                public_ip_url=${OPTARG}
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
	curl -s "$public_ip_url"
}

function updateTitleWithArgs {	
	ipAddress=$(curl -s "$public_ip_url")

	if [ -z "$ipAddress" ]
	then
		updateTitle "No IP Address"
		if [[ "$HELLO_IT_NETWORK_STATE" == "1" ]]
		then
			handleStateUpdate $mode ${STATE[2]}
			updateTooltip "Please, check your Ethernet or WiFi connection"
		else
			handleStateUpdate $mode ${STATE[3]}
			updateTooltip "No internet connection available"
		fi
	else
		updateTitle "Public IP: $ipAddress"
		handleStateUpdate $mode ${STATE[0]}
    	updateTooltip "You should have access to Internet"
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
