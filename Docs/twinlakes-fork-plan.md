# Twin Lakes "IT Help" menu — Hello-IT fork architecture plan

**Status:** planning complete 2026-10-30, open items answered 2026-11-02; ready for a build session. No code written yet.
**Owner:** Andrew (Twin Lakes Tech / HRSD). **Live Support (VHD) Meet URL:** https://meet.google.com/meet/aqb-ncnn-ajr (Andrew, 2026-11-02; Google redirects the short form to this path, so use it verbatim).
**Related:** `design.md` (full Help-Desk Client rewrite, macOS 15+, decided 2026-08-27), `reference/hello-it-analysis.md` (code assessment), `reference/integration-facts.md` (Mosyle/macOS facts, with UNVERIFIED list).

## 0. What this is, and how it relates to the rewrite

This is the **small, whole-fleet, ship-soon** deliverable: a menu-bar item on every Mac that shows
Internet state + network name, local IP, hostname, and a Support submenu (Twin Lakes support site +
Live Support Google Meet). It is built on Hello-IT (BSD-3, ygini/Hello-IT) because every requested
feature is covered by Hello-IT's **existing plugins plus two shell scripts**: no new Objective-C.

`design.md` remains the long-term plan (ticket form, relay, Datto, macOS 15+). This fork does not
replace it. It covers the ~300 Macs that can never run the 15+ client and gets a visible "get help"
path in front of everyone now. When the Help-Desk Client ships, one line in the profile swaps the
Support item from a URL to `public.open.application`.

## 1. Requirements (from Andrew, 2026-10-30)

| # | Requirement | How it is met |
|---|---|---|
| R1 | Menu shows **Internet** with green/red dot **and which network** it is on | `public.script.item` → our `network.sh` (state + "Internet: <SSID>" / "Internet: Ethernet") |
| R2 | **Local IP** under it | upstream `com.github.ygini.hello-it.ip.sh` (click copies IP) |
| R3 | **Hostname** under that | our `hostname.sh` (upstream one is broken, issue #64); shows the Mosyle device name (ComputerName); click copies |
| R4 | **Support ▸** submenu: "Twin Lakes Tech Support" → https://www.twinlakesllc.org/support (verified 200) ; "Live Support" → https://meet.google.com/meet/aqb-ncnn-ajr | `public.submenu` + two `public.open.resource` |
| R5 | Runs on the **entire fleet**: 2012-era Intel through M1 / Neo / M5, macOS **10.13.6 → 27 (Golden Gate)** per Andrew 2026-11-02 | Universal binary, **deployment floor 10.13** (Xcode 26 SDK minimum); see §4 |
| R6 | Pushed by **Mosyle**, however it needs to be | Install PKG (app) + Certificates/Custom Profiles (.mobileconfig with managed preferences); see §6 |
| R7 | Don't over-complicate | No rebrand of the binary, no new plugins, no server. Branding is the menu title + optional icon |

Target menu (exactly the order Andrew asked for):

```
 ●  (menu-bar icon; turns red when Internet is down)
 ● Internet: HRHS-Staff            ← green ok / red error / orange = captive portal
   Local IP: 10.10.48.103
   Hostname: HR11405
   ─────────────────
   Support                       ▸  Twin Lakes Tech Support
                                    Live Support (Google Meet)
```

## 2. Verified facts that shape the plan (checked 2026-10-30)

- **Upstream state:** last push 2023-04-12 (`develop` = v1.7.0-beta1, min macOS 10.14.6, notarytool, script tasks off the main thread). `master` = v1.6.0 (2021). 294 stars, 32 forks, none active since 2024. Issue #71 "macOS 26 compatibility" was closed as the reporter's own build problem; no confirmed breakage of the official pkgs on 14/15/26.
- **It compiles on Xcode 26.6 today.** Smoke build of `master` as a universal (x86_64+arm64) app with `MACOSX_DEPLOYMENT_TARGET=10.13`, unsigned, succeeded after **one patch**: comment out `#import <netinet6/in6.h>` in `src/Hello IT/Reachability.m` (private header under modules; `netinet/in.h` already covers it). Build must go through the scheme (`-scheme "Hello IT"`), not `-target`, so `HITDevKit` builds first. The dead `-UseModernBuildSystem=NO` flag in `package/BuildAndPackage.command` must be dropped. Remaining warnings: ~100 deprecated `asl_log`, a few others; none fatal.
- **Xcode 26 SDK floor is 10.13**, so a 10.13 build is possible if any iMac turns out to be below 10.14.6.
- **Hampshire already ran Hello-IT.** Mosyle has a **disabled Certificates/Custom profile id 6 "HelloIT"** (`HelloIT.mobileconfig`, last modified 2025-08-12, scoped to shared groups CO - Staff, HRHS - Staff, HRHS - Students OLD, NHRES - Staff/Students, NORRIS - Staff/Students; 382 devices). Its payload is `com.apple.ManagedClient.preferences` for domain `com.github.ygini.Hello-IT`, menu title **"IT Help"**, items: Internet (public.test.http against a raw.githubusercontent URL), Managed Software Center, macOS Updates, TeamViewerQS, ip.sh, hostname.sh (`args.format=%C`, the broken syntax). It also carries a profile-removal-password payload (do not copy it forward). The app itself came from the Munki/AutoPkg toolchain (Munki profiles are also disabled). **This is the "old software" still on old devices.** No Install PKG, Custom Command, or App List entry references Hello IT today.
- **SSID on modern macOS:** `ipconfig getsummary en0 | awk -F' SSID : ' '/ SSID : /{print $2}'` works on 26.5 without Location Services (verified locally). `networksetup -getairportnetwork` is blocked on 15+; the `airport` binary is gone since 14.4. Older OSes need the fallbacks (§5.1).
- **Mosyle side (from the KB + Hampshire export):** Install PKG = Management > Install PKG > PKGs tab > Add new package (host on Mosyle CDN; flat pkg; bundle ID + version drive status). Custom .mobileconfig = the **Certificates/Custom Profiles** type (that is what profile id 6 is). Profiles live-reload Hello-IT via the MCX changed-domains notification, so menu edits need no reinstall.
- **Fleet (Mosyle export 2026-08-26, per `design.md` §4):** 1,380 Macs; 926 arm64 (M1 762, Neo 113), 449 Intel (A2179 239, 2015/17 Airs 137, 2013 Airs 15, misc). OS: 26.x 688 · 15.x 395 · 14 37 · 13 17 · 12 174 · 11 23 · 10.15 41. Lowest observed OS is 10.15, inside the 10.14.6 floor. Re-pull before ring 2 (the 2012 iMacs on the staff sheet may not be in that export).

## 3. Decisions

| # | Decision | Choice and why |
|---|---|---|
| F1 | Fork vs. use upstream pkg | **Fork** (`twinlakes-hello-it`, branch from upstream `develop`). Upstream is dormant; we need our own build to fix Xcode 26, own the signing, and own the scripts. Keep upstream remote for cherry-picks. BSD-3: keep LICENSE + copyright notice, add NOTICE line. |
| F2 | Rebrand the binary? | **No.** Keep bundle ID `com.github.ygini.Hello-IT`, app name `Hello IT.app`, support paths `/Library/Application Support/com.github.ygini.hello-it/…`. Users never see the app name (`LSUIElement`); they see the menu title ("IT Help" or "Twin Lakes Tech") and the icon, both set by config. Keeping the IDs lets us reuse profile id 6 and upgrade the old Munki installs in place. Rebrand is a future option, not a v1 task. |
| F3 | Base branch | `develop` (1.7.0-beta1) for its background script tasks, notarytool and dark-mode icon fixes, **rebuilt with `MACOSX_DEPLOYMENT_TARGET=10.13`** (its declared 10.14.6 floor is a project setting, not a known API need; the oldest Mac in service is 10.13.6). Verify the 10.13 build launches on a 10.13 or 10.15 Intel Mac in ring 0. If `develop` will not build or run at 10.13, fall back to `master` + the same patch, which is verified at 10.13 (§2). |
| F4 | Internet item | `public.script.item` (our script), **not** `public.test.http`, because only a script can put the SSID in the title. State: ok = reaches Internet; warning = on a network but captive/no route (sign-in needed); error = no interface/IP; the menu-bar icon aggregates it. |
| F5 | Hostname item | Shows `scutil --get ComputerName` labelled "Hostname:", because that is the Mosyle device name (HR asset number from the Rename Devices profile) that a VHD tech will ask for. LocalHostName/HostName available via option. |
| F6 | Scripts delivery | Inside our pkg, in `CustomScripts/` (same place the stock scripts live). One artifact to version. Root-owned 0755; set `denyUserWritableScript` true in the profile. |
| F7 | Config delivery | One custom `.mobileconfig`, two payloads: `com.apple.ManagedClient.preferences` (menu, Forced) + `com.apple.servicemanagement` (pre-approve the LaunchAgent on 13+ so it cannot be switched off in Login Items and raises no "background item added" nag). Uploaded as a Certificates/Custom profile; **edit profile id 6 in place** (replace file, re-scope, enable) rather than creating a parallel one. |
| F8 | Signing | No Twin Lakes / district Developer ID exists yet (Andrew, 2026-11-02; he has a **personal Apple developer account**). Three tiers: (a) **v1 ships with the self-signed `HelpDesk Client Dev` identity** on the app, unsigned pkg, installed by the Mosyle agent; Login Items rule by `Label` = `com.github.ygini.hello-it`. (b) If Andrew's personal account is a *paid* Developer Program membership, it can issue Developer ID Application + Installer certs → notarized pkg + `TeamIdentifier` rule; acceptable as an interim, but it ties fleet trust to one person's account, so plan to re-sign under an org account later (a re-sign is a version bump, nothing else). A free personal Apple ID cannot issue Developer ID. (c) Org Developer Program enrollment (needs D-U-N-S) is the end state. Whether Mosyle Install PKG accepts an unsigned pkg is still UNVERIFIED → ring 0 answers it; fallback is a Custom Command (`curl` from CDN + `installer -pkg`). |
| F9 | Old installs | Our pkg's `postinstall` removes `/Applications/Hello IT.app` (AutoPkg/Munki location) and any stale LaunchAgent, then bootstraps ours for the console user (`launchctl bootstrap gui/<uid>`, fallback `load` on 10.15). Ship `deploy/uninstall.sh` too (issue #67). |
| F10 | Rollout | Rings mirror the old profile's groups: 0 = IT Macs (Andrew + one Intel A2179 + one M1 + the oldest iMac you can find) → 1 = CO - Staff → 2 = HRHS - Staff → 3 = other schools' staff → 4 = students. Each ring gated on the acceptance list (§7). |

## 4. Fleet coverage matrix

| Hardware / OS | Count (Aug export) | Covered by | Notes |
|---|---|---|---|
| arm64 (M1, Neo, M-series incl. M5) on 15 / 26 | ~900 | universal build, arm64 slice | Login Items payload matters here (13+) |
| Intel A2179 on 14 / 15 | ~240 | x86_64 slice | same |
| Intel 2015/2017 Airs on 12 (Monterey cap) | ~140 | x86_64 slice, floor 10.14.6 | `ipconfig getsummary` fallback path for SSID |
| Intel 2013 Airs on 11 (Big Sur cap) | ~15 | same | |
| 2012-era MBP/iMacs on 10.15 (Catalina cap) | ~41 | same | |
| Oldest known: **10.13.6** (High Sierra) | not in Aug export; on the staff sheet | floor set to 10.13 | ring-0 test target; `ipconfig getsummary` absent → `networksetup`/`airport` fallbacks carry the SSID |
| Newest: **macOS 27 Golden Gate** | growing | arm64 / x86_64 slices | test Login Items payload + menu-bar icon on 27 in ring 0 |
| Anything below 10.13 | 0 known | not covered | retire or leave as is |

## 5. Components

### 5.1 `deploy/scripts/org.twinlakesllc.hello-it.network.sh` (new)
Sources `$HELLO_IT_SCRIPT_SH_LIBRARY/com.github.ygini.hello-it.scriptlib.sh`; implements
`setTitleAction`, `fromCronAction`, `onNetworkAction`, `onClickAction` (copy summary to clipboard).

Logic, in order:
1. Interface: `route -n get 8.8.8.8 | awk -F': ' '/interface:/{print $2}'`; if empty → `updateState error`, title "Internet: Not connected".
2. Port type: `networksetup -listallhardwareports` map device → "Wi-Fi" / "Ethernet" / "USB 10/100/1000 LAN" / "Thunderbolt Bridge"; VPN tunnels (`utun*`) → fall through to the first `en*` with an IPv4.
3. Network name (Wi-Fi only), first that returns non-empty:
   - `ipconfig getsummary "$IF" | awk -F' SSID : ' '/ SSID : /{print $2}'` (14+, verified on 26.5)
   - `networksetup -getairportnetwork "$IF" | sed 's/^Current Wi-Fi Network: //'` (≤13)
   - `/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk -F': ' '/ SSID/{print $2}'` (≤14.3)
   - else "Wi-Fi"
4. Internet test: `curl -s -m 4 -o /dev/null -w '%{http_code}' http://captive.apple.com/hotspot-detect.html` plus body contains `Success` → **ok**; HTTP 200 but no `Success`, or 3xx → **warning** (captive portal; tooltip "Open a browser to sign in to the network"); timeout/error → **error**.
5. Title: `Internet: <SSID>` / `Internet: Ethernet` / `Internet: <SSID> (sign-in needed)` / `Internet: Not connected`.
Profile settings for the item: `repeat` 60 (seconds), `title` "Internet: checking…", `script` = file name.
Rule: no third-party hosts; only Apple's captive endpoint (same host Hello-IT's own Reachability uses).

### 5.2 `deploy/scripts/org.twinlakesllc.hello-it.hostname.sh` (new, replaces upstream)
Title `Hostname: $(scutil --get ComputerName)`; `-f %L` / `-f %H` options via the `options` array (upstream removed `args`; that is bug #64). Click copies the name. Refresh on `fromCronAction` (repeat 300) so a Mosyle rename shows up.

### 5.3 Local IP
Upstream `com.github.ygini.hello-it.ip.sh` unchanged, `options: ["-m","2"]` (show "No IP Address" with state when down). Title already reads "Local IP: x.x.x.x".

### 5.4 `deploy/profile/TwinLakes-HelloIT.mobileconfig`
Payload 1, `com.apple.ManagedClient.preferences`, domain `com.github.ygini.Hello-IT`, `Forced` → `mcx_preference_settings`:
```
functionIdentifier: public.submenu
settings:
  title: "IT Help"                       # or "Twin Lakes Tech" (Andrew's call)
  denyUserWritableScript: true
  content:
    - public.script.item  { script: org.twinlakesllc.hello-it.network.sh, repeat: 60, title: "Internet: checking…" }
    - public.script.item  { script: com.github.ygini.hello-it.ip.sh, options: ["-m","2"], repeat: 60 }
    - public.script.item  { script: org.twinlakesllc.hello-it.hostname.sh, repeat: 300 }
    - public.separator
    - public.submenu { title: "Support", content:
        - public.open.resource { title: "Twin Lakes Tech Support", URL: https://www.twinlakesllc.org/support }
        - public.open.resource { title: "Live Support (Google Meet)", URL: https://meet.google.com/meet/aqb-ncnn-ajr } }
```
Payload 2, `com.apple.servicemanagement` (macOS 13+ ignore on older): `Rules: [{RuleType: Label, RuleValue: com.github.ygini.hello-it}]` now; switch to `TeamIdentifier` once a Developer ID signs the build. No removal-password payload. `PayloadScope: System`.
Root-level `loglevel` only when debugging (every `hitp-*` line lands in the unified log).

### 5.5 Optional branding (config only, no rebuild)
Drop a template PNG set into `/Library/Application Support/com.github.ygini.hello-it/CustomStatusBarIcon/` (names per the wiki) via the pkg for a Twin Lakes glyph. Default is the Hello-IT dot, which already turns red/orange with the aggregate state. Defer unless cheap.

### 5.6 Build + package (`package/BuildAndPackage.command`, patched)
- `xcodebuild -project src/"Hello IT.xcodeproj" -scheme "Hello IT" -configuration Release ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=10.13` (drop `-UseModernBuildSystem=NO`, drop `-target`).
- Team ID + identities from env / `src/CustomSettings.xcconfig` (upstream already supports this); `codesign --options runtime --timestamp`.
- Payload root: `/Applications/Utilities/Hello IT.app`, `/Library/Application Support/com.github.ygini.hello-it/{CustomScripts,CustomStatusBarIcon,CustomImageForItem}`, `/Library/LaunchAgents/com.github.ygini.hello-it.plist`.
- `pkgbuild --identifier com.github.ygini.hello-it --version 1.7.<n>` (must be **greater** than whatever Munki left behind; 1.7.1+ is safe) → `productbuild` → `notarytool submit --wait` + `stapler` when a Developer ID exists.
- Version string also lands in Mosyle's PKG entry; keep them identical.

### 5.7 `postinstall` (ours)
1. Remove `/Applications/Hello IT.app` if present (Munki/AutoPkg era).
2. `chown -R root:wheel` + `chmod 755` on CustomScripts.
3. For the console user: `launchctl bootout gui/$uid/com.github.ygini.hello-it` (ignore errors) then `launchctl bootstrap gui/$uid /Library/LaunchAgents/com.github.ygini.hello-it.plist`; on 10.15 use `launchctl asuser $uid launchctl load`.
4. Exit 0 even with no console user (login will start it).

## 6. Mosyle deployment runbook (Hampshire; read-only until ring 0 is approved)

1. **Build** the pkg (§5.6). Record SHA-256.
2. **Install PKG:** Management > Install PKG > **CDN tab** → upload pkg. **PKGs tab > Add new package > Already have a .PKG** → App name "IT Help (Hello IT)", bundle `com.github.ygini.Hello-IT`, version as built, "Validate file integrity" on, "This app is signed" **off** (agent install; ADE devices). **Profiles tab > Add new profile** → "IT Help – Install" → select PKG → "Install all apps after saving" on, no alert pop-up, not in Self-Service → scope ring 0 only.
3. **Config:** Management > **Certificates/Custom Profiles** → open profile id 6 "HelloIT" → replace the file with `TwinLakes-HelloIT.mobileconfig`, rename "IT Help – Config", scope ring 0, enable. (Backup the old file first per `mosyle-console-change` skill rules; the old file is already captured in `MosyleCert/hampshire/audit/raw/forms/mac_batchB.json`.)
4. **Order:** config profile first, then pkg (the app reads prefs on launch; it also live-reloads).
5. **Ring 0 verification** per §7; then widen scope one ring at a time (edit scopes on both profiles together).
6. **Housekeeping after ring 4:** delete the disabled Munki/MunkiReport custom profiles only if the audit's open question "is Munki gone" is settled (separate change).

Each production step goes through the `mosyle-console-change` skill (plan, backups named BACKUP, read-before/after). Nothing in this document is approval to change production.

## 7. Acceptance tests (per ring, Intel + arm64, oldest OS in the ring)

- Menu appears within 60 s of login; survives reboot and logout/login; no Quit item; killing the process relaunches it (KeepAlive).
- Internet line is **green with the real SSID** on Wi-Fi; **"Internet: Ethernet"** on a dock; **red** within 60 s of turning Wi-Fi off; orange on a captive network (test at a guest portal if one exists).
- Local IP matches `ipconfig getifaddr en0`; click copies it.
- Hostname matches the Mosyle device name; click copies it.
- Support ▸ both links open in the default browser; Meet opens the right room.
- macOS 13+: System Settings > General > Login Items shows "Hello IT" enabled and greyed out (managed); no "Background items added" banner.
- Old device: `/Applications/Hello IT.app` gone, `/Applications/Utilities/Hello IT.app` is the new version (`defaults read … CFBundleShortVersionString`).
- Mosyle: Install PKG status "Installed"; profile status "Installed" on Device Info.
- Unified log shows no `hitp-log-err` lines for 10 min of normal use.
- Editing the Meet URL in the profile and saving updates the menu without reinstall (live reload).

## 8. Enhancements to decide later (not v1)

- **VHD hours awareness:** make "Live Support" a script item that is green and enabled during staffed hours and greyed otherwise (hours in the profile, or later from the relay in `design.md`). Cheap once v1 ships.
- **⌥-only tech row** (`optionalDisplay: true`): Serial number, macOS version, Mosyle agent running, "Copy diagnostics". Techs on the Meet call ask the user to hold Option.
- **Role menus** via `allowSubdomains` + a second profile scoped to staff (e.g., staff see a Zendesk link, students do not).
- **Twin Lakes icon** (§5.5). **Rebrand** of bundle/paths (F2) only if a second customer needs a visibly different product.
- Replace `asl_log` with `os_log` in the fork when touching the code anyway (cosmetic; warnings only).

## 9. Open items owed by humans

- ~~Google Meet URL~~ → https://meet.google.com/meet/aqb-ncnn-ajr (2026-11-02). Still open: menu title, "IT Help" (what Hampshire staff already saw) vs. "Twin Lakes Tech".
- ~~Developer ID~~ → none for the org yet; Andrew has a personal Apple developer account (paid or free: Andrew checks at developer.apple.com/account → Membership). Not blocking ring 0 (F8 tier a).
- ~~Oldest OS~~ → 10.13.6; newest macOS 27. Floor fixed at 10.13 (F3). Still open: find one 10.13.6 Mac for ring 0.
- Approval to touch profile id 6 and to create the Install PKG entry (production change).

## 10. Fresh-session kickoff (build order)

1. `git clone https://github.com/ygini/Hello-IT` → new repo `twinlakes-hello-it` (GitHub, public, BSD-3 retained), branch `tlt/main` from `develop`; add upstream remote. Local path suggestion: `~/Developer/twinlakes-hello-it`. (The zip in `~/Downloads/Hello-IT-master.zip` is `master`; prefer the clone.)
2. Apply the Reachability patch; build the scheme universal with Xcode 26.6 (`/Applications/Xcode-26.6.0.app`) at `MACOSX_DEPLOYMENT_TARGET=10.13`; confirm `lipo -info` shows x86_64 arm64 and `LSMinimumSystemVersion` 10.13. If `develop` fails at 10.13, repeat on `master` (verified).
3. Write §5.1 and §5.2 scripts; unit-test them by hand on this Mac (`HELLO_IT_SCRIPT_SH_LIBRARY=src/Plugins/ScriptedItem/scriptLibraries/bash bash script.sh title`), then Wi-Fi off, then a dock.
4. Write §5.4 profile; load it locally with `sudo profiles install -path …` (or `defaults write com.github.ygini.Hello-IT …` for a quick look); run the built app from Xcode; iterate on titles.
5. Patch `BuildAndPackage.command` (§5.6), write `postinstall` + `uninstall.sh` (§5.7), build the pkg, install on this Mac, run the §7 list locally.
6. Ring 0 in Mosyle per §6 via the `mosyle-console-change` skill.
7. Write `deploy/mosyle/README.md` (the §6 steps with screenshots) and tag `v1.7.1-tlt1`.

Local environment checked 2026-10-30: macOS 26.5.2 arm64, Xcode 26.6 (17F113), `notarytool` 1.1.2, `pkgbuild`/`productbuild` present, signing identities available: `HelpDesk Client Dev` only (no Developer ID).
