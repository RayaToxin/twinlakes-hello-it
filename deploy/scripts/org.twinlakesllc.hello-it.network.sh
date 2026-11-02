#!/bin/bash

# org.twinlakesllc.hello-it.network.sh
# Twin Lakes "IT Help" menu: Internet state + network name.
#
# Menu item for Hello-IT (public.script.item). Shows:
#   Internet: <SSID>                   ok      (green)  reaches the Internet over Wi-Fi
#   Internet: Ethernet                 ok      (green)  reaches the Internet over a wired port
#   Internet: <SSID> (sign-in needed)  warning (orange) on a network behind a captive portal
#   Internet: <SSID> (no Internet)     error   (red)    on a network, Internet unreachable
#   Internet: Not connected            error   (red)    no interface with a default route
# Click copies a one-line summary (state, network, interface, IP, gateway) to the clipboard.
#
# Only Apple's captive-portal endpoint is contacted (the same host Hello-IT's own
# Reachability check uses). No third-party hosts.
#
# Profile settings: script = this file name, repeat = 60, network = true,
#                   title = "Internet: checking…"

. "$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh"

CAPTIVE_URL="http://captive.apple.com/hotspot-detect.html"
CAPTIVE_TIMEOUT=4

AIRPORT_BIN="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

# ---------------------------------------------------------------------------
# Interface discovery
# ---------------------------------------------------------------------------

# BSD name of the interface carrying the default route (may be a VPN tunnel).
function routeInterface {
    route -n get 8.8.8.8 2>/dev/null | awk -F': ' '/interface:/{print $2; exit}'
}

# First "up" en* interface holding an IPv4 address; used when the default
# route points at a tunnel (utun*, ipsec*, ppp*) so the physical port is shown.
function firstPhysicalInterfaceWithIPv4 {
    local iface
    for iface in $(ifconfig -lu 2>/dev/null); do
        case "$iface" in
            en[0-9]*)
                if ifconfig "$iface" 2>/dev/null | grep -q 'inet '; then
                    echo "$iface"
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# "Hardware Port" label for a BSD device, from networksetup (e.g. "Wi-Fi",
# "Ethernet", "USB 10/100/1000 LAN", "Thunderbolt Bridge").
function hardwarePortForInterface {
    networksetup -listallhardwareports 2>/dev/null | awk -v dev="$1" '
        /^Hardware Port: /{ port = substr($0, 16) }
        /^Device: /       { if ($2 == dev) { print port; exit } }'
}

function ipv4ForInterface {
    ifconfig "$1" 2>/dev/null | awk '/inet /{print $2; exit}'
}

function gatewayForRoute {
    route -n get 8.8.8.8 2>/dev/null | awk -F': ' '/gateway:/{print $2; exit}'
}

# ---------------------------------------------------------------------------
# SSID (Wi-Fi only). Each method is tried in turn; "<redacted>" and empty
# results are discarded. macOS 14+ redacts the SSID for processes without
# Location Services authorization, so "Wi-Fi" is the final fallback.
# ---------------------------------------------------------------------------

function cleanSSID {
    local s="$1"
    case "$s" in
        ""|"<redacted>"|"<SSID Redacted>") return 1 ;;
    esac
    echo "$s"
}

function ssidForInterface {
    local iface="$1" s

    # macOS 14+ (verified on 26.5 when the caller has Location authorization)
    s=$(ipconfig getsummary "$iface" 2>/dev/null | awk -F' SSID : ' '/ SSID : /{print $2; exit}')
    cleanSSID "$s" && return 0

    # macOS 13 and earlier (prints "You are not associated..." on 15+)
    s=$(networksetup -getairportnetwork "$iface" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')
    cleanSSID "$s" && return 0

    # macOS 14.3 and earlier (binary removed in 14.4)
    if [ -x "$AIRPORT_BIN" ]; then
        s=$("$AIRPORT_BIN" -I 2>/dev/null | awk -F': ' '/^ *SSID: /{print $2; exit}')
        cleanSSID "$s" && return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Internet test against Apple's captive-portal endpoint.
# Prints: ok | captive | down
# ---------------------------------------------------------------------------

function internetTest {
    local body code
    body=$(mktemp -t hello-it-net) || { echo down; return; }
    code=$(curl -s -m "$CAPTIVE_TIMEOUT" -o "$body" -w '%{http_code}' "$CAPTIVE_URL" 2>/dev/null)
    local rc=$?
    local result="down"

    if [ $rc -eq 0 ]; then
        case "$code" in
            200)
                if grep -q 'Success' "$body" 2>/dev/null; then
                    result="ok"
                else
                    result="captive"
                fi
                ;;
            3[0-9][0-9])
                result="captive"
                ;;
            *)
                result="down"
                ;;
        esac
    fi

    rm -f "$body"
    echo "$result"
}

# ---------------------------------------------------------------------------
# Main check: compute title/state/tooltip and (optionally) a clipboard summary
# ---------------------------------------------------------------------------

NET_SUMMARY=""

function checkNetwork {
    local routeIF physIF iface port isWifi=0 netName ssid ip gw test title tooltip state

    routeIF=$(routeInterface)

    if [ -z "$routeIF" ]; then
        updateTitle "Internet: Not connected"
        updateState "${STATE[2]}"
        updateTooltip "No network connection. Check Wi-Fi or the Ethernet cable.\nClick to copy a summary."
        NET_SUMMARY="Internet: Not connected (no default route)"
        return
    fi

    iface="$routeIF"
    case "$routeIF" in
        utun*|ipsec*|ppp*|tun*|tap*)
            # Default route is a VPN tunnel: report the physical port under it.
            # A tunnel with no physical interface (Wi-Fi just switched off) is
            # not a connection at all.
            physIF=$(firstPhysicalInterfaceWithIPv4)
            if [ -n "$physIF" ]; then
                iface="$physIF"
            else
                updateTitle "Internet: Not connected"
                updateState "${STATE[2]}"
                updateTooltip "No network connection. Check Wi-Fi or the Ethernet cable.\nClick to copy a summary."
                NET_SUMMARY="Internet: Not connected (default route via $routeIF, no physical interface with an IPv4 address)"
                return
            fi
            ;;
    esac

    port=$(hardwarePortForInterface "$iface")

    case "$port" in
        *Wi-Fi*|*AirPort*) isWifi=1 ;;
    esac

    if [ $isWifi -eq 1 ]; then
        ssid=$(ssidForInterface "$iface")
        netName="${ssid:-Wi-Fi}"
    else
        netName="Ethernet"
    fi

    ip=$(ipv4ForInterface "$iface")
    gw=$(gatewayForRoute)
    test=$(internetTest)

    case "$test" in
        ok)
            title="Internet: $netName"
            state="${STATE[0]}"
            tooltip="Connected to the Internet via ${port:-$iface} ($iface).\nClick to copy a summary."
            ;;
        captive)
            title="Internet: $netName (sign-in needed)"
            state="${STATE[1]}"
            tooltip="This network needs a sign-in. Open a browser to sign in to the network.\nClick to copy a summary."
            ;;
        *)
            title="Internet: $netName (no Internet)"
            state="${STATE[2]}"
            tooltip="Connected to ${port:-$iface} ($iface) but the Internet is not reachable.\nClick to copy a summary."
            ;;
    esac

    updateTitle "$title"
    updateState "$state"
    updateTooltip "$tooltip"

    NET_SUMMARY="$title [$test] via ${port:-unknown port} ($iface), IP ${ip:-none}, gateway ${gw:-none}, route via $routeIF"
}

function setTitleAction {
    checkNetwork
}

function fromCronAction {
    checkNetwork
}

function onNetworkAction {
    checkNetwork
}

function onClickAction {
    checkNetwork
    printf '%s' "$NET_SUMMARY" | pbcopy
}

main "$@"

exit 0
