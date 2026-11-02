# deploy/ — Twin Lakes "IT Help" menu

Fleet artifacts for the Hello-IT fork. The plan with all decisions is `Docs/twinlakes-fork-plan.md`.

| Path | Purpose |
|---|---|
| `scripts/org.twinlakesllc.hello-it.network.sh` | Internet item: state (green/orange/red) + network name; click copies a summary |
| `scripts/org.twinlakesllc.hello-it.hostname.sh` | Hostname item: `scutil --get ComputerName` (the Mosyle device name); click copies |
| `profile/TwinLakes-HelloIT.mobileconfig` | Managed preferences (menu) + managed Login Item; upload as a Mosyle Certificates/Custom profile |
| `pkg_scripts/postinstall` | Removes the Munki-era `/Applications/Hello IT.app`, locks down scripts, (re)starts the LaunchAgent |
| `uninstall.sh` | Full removal (also installed at `/Library/Application Support/com.github.ygini.hello-it/uninstall.sh`) |

## Build the pkg

```
tools/setup-dev-signing-keychain.sh      # once per dev Mac (needs ~/.local/share/helpdesk-client-dev-cert/)
package/BuildAndPackage.command          # -> package/build/<ver>-Release/TwinLakes-HelloIT-<ver>-Release.pkg + SHA-256
```

The build is universal (x86_64 + arm64), deployment floor macOS 10.13, app signed with the
self-signed `HelpDesk Client Dev` identity, pkg unsigned (plan F8 tier a). To sign and notarize
once a Developer ID exists:

```
CUSTOM_DEVELOPER_ID_APP="Developer ID Application: …" \
CUSTOM_DEVELOPER_ID_INSTALLER="Developer ID Installer: …" \
CUSTOM_DEVELOPMENT_TEAM=TEAMID NOTARYTOOL_PROFILE=<keychain profile> CODESIGN_KEYCHAIN=none \
package/BuildAndPackage.command
```

Bump `MARKETING_VERSION` in `src/Hello-IT.xcconfig` for every pkg that goes to Mosyle (the
version drives Mosyle's install status; it must stay above the Munki-era 1.7.0).

## Test the scripts by hand

```
export HELLO_IT_SCRIPT_SH_LIBRARY=src/Plugins/ScriptedItem/scriptLibraries/bash
bash deploy/scripts/org.twinlakesllc.hello-it.network.sh title      # also: periodic-run | network | run
HELLO_IT_OPTIONS_AVAILABLE=yes HELLO_IT_OPTIONS="-f %L " \
  bash deploy/scripts/org.twinlakesllc.hello-it.hostname.sh title -f %L
```

## Test the menu locally without MDM

`profiles install` cannot load a configuration profile on macOS 11+, so for a local look:

```
python3 - <<'EOF2'
import plistlib
p = plistlib.load(open('deploy/profile/TwinLakes-HelloIT.mobileconfig','rb'))
mcx = p['PayloadContent'][0]['PayloadContent']['com.github.ygini.Hello-IT']['Forced'][0]['mcx_preference_settings']
plistlib.dump(mcx, open('/tmp/hello-it-prefs.plist','wb'))
EOF2
defaults import com.github.ygini.Hello-IT /tmp/hello-it-prefs.plist
sudo installer -pkg package/build/1.7.1-Release/TwinLakes-HelloIT-1.7.1-Release.pkg -target /
```

Live reload and the managed (greyed-out) Login Item only happen with the profile delivered by
MDM; test those in ring 0. To see the app's own log lines: `/usr/bin/log stream --info --predicate 'process == "Hello IT"'`
(use the full path; `log` is a zsh builtin).

## Known limit: SSID on macOS 26

Every SSID source (`ipconfig getsummary`, `wdutil`, `system_profiler`, `ioreg`, CoreWLAN) returns
`<redacted>` unless the calling process has Location Services authorization. Hello IT never asks
for it, so on 26.x the Internet item reads `Internet: Wi-Fi` (state is still correct). Older
systems fall back to `networksetup -getairportnetwork` / `airport -I`. See the plan, section 5.1.
