#!/bin/bash

# org.twinlakesllc.hello-it.hostname.sh
# Twin Lakes "IT Help" menu: computer name.
#
# Menu item for Hello-IT (public.script.item). Shows "Hostname: <ComputerName>",
# the name Mosyle sets through its Rename Devices profile and the name a tech
# sees in the Mosyle console. Click copies the name to the clipboard.
#
# Replaces upstream com.github.ygini.hello-it.hostname.sh, which still reads the
# removed "args" dictionary (upstream issue #64) and so ignores its format.
#
# Option (via the "options" array in the profile):
#   -f FORMAT   %C computer name (default), %L local host name (Bonjour),
#               %H host name. Several may be combined, e.g. "-f %C (%L)".
#
# Profile settings: script = this file name, repeat = 300 (so a Mosyle rename
#                   shows up within 5 minutes), title = "Hostname: …"

. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

format="%C"

function handleOptions {
    local o
    OPTIND=1
    while getopts "f:" o; do
        case "${o}" in
            f) format="${OPTARG}" ;;
        esac
    done
}

function getHostname {
    local computername localhostname hostname result

    computername=$(scutil --get ComputerName 2>/dev/null)
    localhostname=$(scutil --get LocalHostName 2>/dev/null)
    hostname=$(scutil --get HostName 2>/dev/null)

    # scutil --get HostName fails when HostName is not set; fall back to the
    # kernel host name so %H still shows something useful.
    [ -z "$hostname" ] && hostname=$(hostname 2>/dev/null)

    result="$format"
    result="${result//%C/$computername}"
    result="${result//%L/$localhostname}"
    result="${result//%H/$hostname}"

    echo "$result"
}

function updateTitleWithHostname {
    local name
    name=$(getHostname)

    if [ -z "$name" ]; then
        updateTitle "Hostname: unknown"
        updateTooltip "Could not read the computer name"
    else
        updateTitle "Hostname: $name"
        updateTooltip "Click to copy the computer name"
    fi
}

function onClickAction {
    updateTitleWithHostname
    printf '%s' "$(getHostname)" | pbcopy
}

function fromCronAction {
    updateTitleWithHostname
}

function setTitleAction {
    updateTitleWithHostname
}

function onNetworkAction {
    updateTitleWithHostname
}

main "$@"

exit 0
