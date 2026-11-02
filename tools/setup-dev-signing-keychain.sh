#!/bin/bash

# setup-dev-signing-keychain.sh
#
# Creates a dedicated keychain holding the self-signed "HelpDesk Client Dev" identity
# with its private key pre-authorized for codesign, so builds run unattended (the copy
# in the login keychain prompts for access on every use, which hangs headless builds).
#
# Reads:  ~/.local/share/helpdesk-client-dev-cert/{key.pem,cert.pem}   (never in a repo)
# Writes: ~/Library/Keychains/helpdesk-dev.keychain-db
#         ~/.local/share/helpdesk-client-dev-cert/keychain.pass  (0600; the keychain password)
#
# package/BuildAndPackage.command picks the keychain up automatically when both exist.
# Re-run at any time; it recreates the keychain from the PEM files.

set -e

CERT_DIR="${HOME}/.local/share/helpdesk-client-dev-cert"
KEYCHAIN="${HOME}/Library/Keychains/helpdesk-dev.keychain-db"
PASS_FILE="${CERT_DIR}/keychain.pass"
IDENTITY_NAME="HelpDesk Client Dev"

[ -f "${CERT_DIR}/key.pem" ] && [ -f "${CERT_DIR}/cert.pem" ] || { echo "Missing ${CERT_DIR}/key.pem or cert.pem" >&2; exit 1; }

if [ -f "${PASS_FILE}" ]; then
	KC_PASS=$(cat "${PASS_FILE}")
else
	KC_PASS=$(/usr/bin/openssl rand -hex 24)
	( umask 077; printf '%s' "${KC_PASS}" > "${PASS_FILE}" )
fi

P12_PASS=$(/usr/bin/openssl rand -hex 16)
P12_TMP=$(mktemp -t helpdesk-dev-p12)
trap 'rm -f "${P12_TMP}"' EXIT

/usr/bin/openssl pkcs12 -export \
	-inkey "${CERT_DIR}/key.pem" -in "${CERT_DIR}/cert.pem" \
	-name "${IDENTITY_NAME}" -passout "pass:${P12_PASS}" -out "${P12_TMP}"

if [ -f "${KEYCHAIN}" ]; then
	security delete-keychain "${KEYCHAIN}" 2>/dev/null || true
fi

security create-keychain -p "${KC_PASS}" "${KEYCHAIN}"
security set-keychain-settings "${KEYCHAIN}"            # no auto-lock, no lock on sleep
security unlock-keychain -p "${KC_PASS}" "${KEYCHAIN}"
security import "${P12_TMP}" -k "${KEYCHAIN}" -P "${P12_PASS}" -f pkcs12 \
	-T /usr/bin/codesign -T /usr/bin/productsign -T /usr/bin/security -T /usr/bin/productbuild -T /usr/bin/pkgbuild
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KC_PASS}" "${KEYCHAIN}" >/dev/null

echo "Keychain ready: ${KEYCHAIN}"
security find-identity -v -p codesigning "${KEYCHAIN}"
