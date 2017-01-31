#!/bin/bash
# Pending Updates Script for Managed Software Center
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

# Computer Details
serial="$(system_profiler SPHardwareDataType | grep "Serial Number" | awk -F":" '{print $2}')"
uuid="$(system_profiler SPHardwareDataType | grep "Hardware UUID" | awk -F":" '{print $2}')"
model="$(system_profiler SPHardwareDataType | grep -i "Model Name" | awk -F":" '{print $2}')"
modelid="$(system_profiler SPHardwareDataType | grep -i "Identifier" | awk -F":" '{print $2}')"
modeldesc="$(curl -s http://support-sp.apple.com/sp/product?cc="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}' | cut -c 9-)" | sed 's|.*<configCode>\(.*\)</configCode>.*|\1|')"
osversion="$(sw_vers | grep "ProductVersion" | awk '{print $2}')"
buildversion="$(sw_vers | grep "Build" | awk '{print $2}')"
storagecmd="$(df -H / | grep "/" | awk '{print $3" / "$2 " Used,",$5 " used"}')"
storage="${storagecmd//%/%25}"
smartstatus="$(diskutil info disk0 | awk '/SMART Status/ {print $3,$4}')"
memory="$(system_profiler SPHardwareDataType | grep "Memory:" | cut -d":" -f2)"
# Network Details
compname="$(/usr/sbin/scutil --get LocalHostName)"
macaddr="$(python -c "from uuid import getnode; print hex(getnode())[2:]")"
ipaddr="$(python -c "import socket; print socket.gethostbyname(socket.gethostname())")"
manifest="$(defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier 2> /dev/null)"
pendingupdates="$(defaults read /Library/Preferences/ManagedInstalls.plist PendingUpdateCount)"

function onClickAction {
link="mailto:?Subject=Computer%20Information%20from%20Hello-IT&Body=-%20Computer%20Details%20-%0ASerial%20Number%3A%20${serial}%0AHardware%20UUID%3A%20${uuid}%0AModel%3A%20${model}%0AModel%20Identifier%3A%20${modelid}%0AModel%20Description%3A%20${modeldesc}%0AmacOS%20Version%3A%20${osversion}%0AmacOS%20Build%3A%20${buildversion}%0ATotal%20Storage%3A%20${storage}%0ASMART%20Status%3A%20${smartstatus}%0ATotal%20RAM%3A%20${memory}%0A-%20Network%20Details%20-%0AComputer%20Name%3A%20${compname}%0AMAC%20Address%20%28Current%20Interface%29%3A%20${macaddr}%0AIP%20Address%20%28Current%20Interface%29%3A%20${ipaddr}%0A-%20Munki%20Details%20-%0AManifest%3A%20${manifest}%0APending%20Updates%3A%20${pendingupdates}"
open "${link// /%20}"
}

function setTitleAction {
  updateTitle "Email Computer Details"
  updateTooltip "Sets up Email to send to IT"
  setEnabled YES
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"
exit 0
