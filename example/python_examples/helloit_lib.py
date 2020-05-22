#!/usr/bin/env python3

class HelloIT(object):
    def handleOptions(self):
        """override this function if you need to parse your options array before everything else"""
        return self

    def onClickAction(self):
        """override this function to specify what to do when the user click on your menu item"""
        return self

    def onNetworkAction(self):
        """override this function to specify what to do when the network change"""
        return self

    def fromCronAction(self):
        """override this function to specify what to do when the script is on a periodic run"""
        return self

    def fromNotificationAction(self):
        """override this function to specify what to do when the script is on a periodic run"""
        return self

    def setTitleAction(self):
        """override this function to specify the item title when UI is loaded (optional, use it
        when your title is always dynamic and can't have a default value). For default value
        use the title key in Hello IT's settings."""
        return self

    def updateState(self, position):
        """usage: updateState(0)
        supported states are managed by the STATE array
        STATE[0] --> OK (Green light)
        STATE[1] --> Warning (Orange light)
        STATE[2] --> Error (Red light)
        STATE[3] --> Unavailable (Empty circle)
        STATE[4] --> No state to display (Nothing at all)"""
        self.STATE = ("ok", "warning", "error", "unavailable", "none")
        print(f"hitp-state: {self.STATE[position]}")

    def updateTitle(self, arg):
        """usage: updateTitle("My new title")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-title: {arg}")

    def setEnabled(self, arg):
        """ usage: setEnabled("YES")
        upported values are YES or NO as string"""
        print(f"hitp-enabled: {arg}")

    def setHidden(self, arg):
        """usage: setHidden("YES")
        supported values are YES or NO as string"""
        print(f"hitp-hidden: {arg}")

    def updateTooltip(self, arg):
        """usage: updateTooltip("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-tooltip: {arg}")

    def sendNotification(self, arg):
        """usage: sendNotification("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-notification: {arg}")

    def emergencyLog(self, arg):
        """usage: emergencyLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-emerg: {arg}")

    def alertLog(self, arg):
        """usage: alertLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-alert: {arg}")

    def criticalLog(self, arg):
        """usage: criticalLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-crit: {arg}")

    def errorLog(self, arg):
        """usage: errorLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-err: {arg}")

    def warningLog(self, arg):
        """usage: warningLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-warning: {arg}")

    def noticeLog(self, arg):
        """usage: noticeLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-notice: {arg}")

    def infoLog(self, arg):
        """usage: infoLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-info: {arg}")

    def debugLog(self, arg):
        """usage: debugLog("This aren't the droids you're looking for")
        first arg only will be used as new title, don't forget quotes"""
        print(f"hitp-log-debug: {arg}")
