#!/bin/bash

function updateTitleWithMainIP {
	ipAddress=""
	globalNetworkState="$3"
	
	mainBSDInterface=$(route -n get 8.8.8.8 | grep "interface: " | awk -F ": " '{print $2}')
	ipAddress=$(ifconfig "$mainBSDInterface" | grep "inet " | sed "s/.*inet \([0-9.]*\).*/\1/" | head -n1)
	
	if [ -z "$ipAddress" ]
	then
		echo "hitp-title: No IP Address"
		if [[ "$globalNetworkState" == "1" ]]
		then
			echo "hitp-state: error"
			echo "hitp-tooltip: Please, check your Ethernet or WiFi connection"
		else
			echo "hitp-state: unavailable"
			echo "hitp-tooltip: No network connection available"
		fi
	else
		echo "hitp-title: $ipAddress"
		echo "hitp-state: ok"
		echo "hitp-tooltip: Having an IP address doesn't mean you've Internet access"
	fi
}
echo "hitp-enabled: NO"
updateTitleWithMainIP
echo "hitp-enabled: YES"

exit 0
