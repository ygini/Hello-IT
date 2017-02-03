#!/bin/bash
# Pending Updates Script for Managed Software Center
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

# Alert if uptime greater than alertcount
alertcount=15
# Warn if uptime greater than warningcount
warningcount=10


function onClickAction {
  setTitleAction "$@"
}

function fromCronAction {
  setTitleAction "$@"
}

function setTitleAction {
  rebootdate="$(last reboot | awk 'NR==1 {print $3,$4,$5,$6}')"
  uptimedays="$(uptime | awk '{print $3}')"
  uptimehours="$(uptime | awk -F, '{print $2}')"
  if [[ $uptimedays -lt $warningcount ]]; then
      echo "Time since last reboot: $uptimedays day and $uptimehours hours"
      updateState "${STATE[0]}"
      updateTitle "Time since Reboot: $uptimedays day, $uptimehours hours"
      updateTooltip "Last Reboot: $rebootdate"
  elif [[ $uptimedays -ge $alertcount ]]; then
      echo "Time since last reboot: $uptimedays days and $uptimehours hours"
      updateState "${STATE[2]}"
      updateTitle "Time since Reboot: $uptimedays day, $uptimehours hours"
      updateTooltip "Last Reboot: $rebootdate"
  else
    echo "Time since last reboot: $uptimedays days and $uptimehours hours"
    updateState "${STATE[1]}"
    updateTitle "Time since Reboot: $uptimedays day, $uptimehours hours"
    updateTooltip "Last Reboot: $rebootdate"
  fi
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"
exit 0
