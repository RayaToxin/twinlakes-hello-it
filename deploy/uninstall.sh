#!/bin/bash

# uninstall.sh: remove the Twin Lakes "IT Help" menu (Hello IT) from this Mac.
# Run as root:  sudo /bin/bash uninstall.sh
#
# Removes the LaunchAgent, the app, the support folder (custom scripts, icons),
# the old Munki-era copy, and the package receipt. It does not remove the
# configuration profile: that is managed by Mosyle.

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo /bin/bash $0" >&2
    exit 1
fi

LABEL="com.github.ygini.hello-it"
AGENT_PLIST="/Library/LaunchAgents/${LABEL}.plist"
APP_PATH="/Applications/Utilities/Hello IT.app"
OLD_APP_PATH="/Applications/Hello IT.app"
SUPPORT_DIR="/Library/Application Support/com.github.ygini.hello-it"
PKG_ID="com.github.ygini.hello-it"

# Stop the agent for every logged-in user
for user in $(who | awk '{print $1}' | sort -u); do
    uid=$(id -u "$user" 2>/dev/null) || continue
    launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null
    launchctl asuser "${uid}" launchctl unload "${AGENT_PLIST}" 2>/dev/null
    home=$(dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [ -n "$home" ] && rm -f "${home}/Library/LaunchAgents/${LABEL}.plist"
done
pkill -x "Hello IT" 2>/dev/null

rm -f "${AGENT_PLIST}"
rm -rf "${APP_PATH}" "${OLD_APP_PATH}" "${SUPPORT_DIR}"
pkgutil --forget "${PKG_ID}" >/dev/null 2>&1

echo "Hello IT removed. The 'IT Help' configuration profile (if any) is removed by Mosyle."
exit 0
