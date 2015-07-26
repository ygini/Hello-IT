#!/bin/bash

function updateTitleWithMainIP {
	ipFound="no"
	
	while read line 
	do 
		ip=$(networksetup -getinfo "$line" | grep "IP" | grep -v "IPv6" |  cut -f2- -d ':' | xargs)
		if [ -n "$ip" ] 
		then
			if [[ "$ip" != "169.254.*" ]]
			then
				echo "hitp-title: $ip"
				echo "hitp-state: ok"
				ipFound="yes"
				break
			fi
		fi
	done < <(networksetup -listnetworkserviceorder | grep "(\d)" | cut -f2- -d ' ')

	if [[ "$ipFound" == "no" ]]
	then
		echo "hitp-title: No IP Address"
		echo "hitp-state: error"
	fi
}
echo "hitp-enabled: NO"
updateTitleWithMainIP
echo "hitp-enabled: YES"

exit 0
