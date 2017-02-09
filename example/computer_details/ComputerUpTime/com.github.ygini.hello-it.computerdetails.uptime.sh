#!/bin/bash
# Pending Updates Script for Managed Software Center
### The following line load the Hello IT bash script lib
. "$HELLO_IT_SCRIPT_FOLDER/com.github.ygini.hello-it.scriptlib.sh"

# Alert if uptime greater than alertcount
alertcount=15
# Warn if uptime greater than warningcount
warningcount=7


function onClickAction {
  osascript -e 'tell app "loginwindow" to «event aevtrrst»'
}

function fromCronAction {
  setTitleAction "$@"
}

function setTitleAction {
  rebootdate="$(date -r "$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')" "+%+")"
  lastboot="$(date -r "$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')" "+%s")"
  now="$(date +"%s")"
  diff="$(( (now - lastboot) / 86400 ))"
  if [[ $diff -lt $warningcount ]]; then # Diff < 7
      echo "Time since last reboot: $diff day(s)."
      updateState "${STATE[0]}"
      updateTitle "Time since Reboot: $diff day(s)."
      updateTooltip "Last Reboot: $rebootdate. Click to restart."
  elif [[ $diff -gt $alertcount ]]; then # Diff > 15
      echo "Time since last reboot: $diff day(s)."
      updateState "${STATE[2]}"
      updateTitle "Time since Reboot: $diff day(s)."
      updateTooltip "Last Reboot: $rebootdate. Click to restart."
  else # 7 <= Diff < 15
      echo "Time since last reboot: $diff day(s)."
      updateState "${STATE[1]}"
      updateTitle "Time since Reboot: $diff day(s)."
      updateTooltip "Last Reboot: $rebootdate. Click to restart."
  fi
}

### The only things to do outside of a bash function is to call the main function defined by the Hello IT bash lib.
main "$@"
exit 0
