#!/bin/bash

# BuildAndPackage.command — Twin Lakes "IT Help" menu (Hello IT fork)
#
# Builds the "Hello IT" scheme as a universal (x86_64 + arm64) app with a macOS 10.13
# deployment floor, signs it, assembles the payload (app, LaunchAgent, custom scripts,
# uninstall script) and produces a flat distribution pkg.
#
# Environment overrides (all optional):
#   CUSTOM_DEVELOPER_ID_APP        codesign identity for the app       (default: "HelpDesk Client Dev")
#   CUSTOM_DEVELOPER_ID_INSTALLER  productsign identity for the pkg    (default: none -> unsigned pkg)
#   CUSTOM_DEVELOPMENT_TEAM        DEVELOPMENT_TEAM for xcodebuild     (default: empty)
#   NOTARYTOOL_PROFILE             notarytool keychain profile name; when set together with an
#                                  installer identity, the pkg is notarized and stapled
#   DEVELOPER_DIR                  Xcode to use (default: /Applications/Xcode-26.6.0.app if present)
#   CODESIGN_KEYCHAIN              keychain holding the app identity with codesign pre-authorized
#                                  (default: ~/Library/Keychains/helpdesk-dev.keychain-db, made by
#                                  tools/setup-dev-signing-keychain.sh). When it exists, the user
#                                  keychain search list is narrowed to it for the duration of the
#                                  build and restored afterwards, so signing never waits on a
#                                  keychain dialog. Set to "none" to skip.
#   CODESIGN_KEYCHAIN_PASSWORD_FILE file holding that keychain's password
#                                  (default: ~/.local/share/helpdesk-client-dev-cert/keychain.pass)
#   FORCE_SKIP_REPO_STATE          set to 1 to build a Release with uncommitted changes
#   FORCE_CONFIGURATION            Release or Debug (default: Release on master/release*/tlt/*, else Debug)
#
# Output: package/build/<version>-<configuration>/TwinLakes-HelloIT-<version>-<configuration>.pkg
# (plus Products/ and dSYM/ next to it). The SHA-256 of the pkg is printed at the end.

set -o pipefail

DEFAULT_DEVELOPER_ID_APP="HelpDesk Client Dev"
DEVELOPER_ID_APP=${CUSTOM_DEVELOPER_ID_APP:-${DEFAULT_DEVELOPER_ID_APP}}
DEVELOPER_ID_INSTALLER=${CUSTOM_DEVELOPER_ID_INSTALLER:-}
DEVELOPMENT_TEAM=${CUSTOM_DEVELOPMENT_TEAM:-}
NOTARYTOOL_PROFILE=${NOTARYTOOL_PROFILE:-}

if [ -z "${DEVELOPER_DIR}" ] && [ -d "/Applications/Xcode-26.6.0.app/Contents/Developer" ]; then
	export DEVELOPER_DIR="/Applications/Xcode-26.6.0.app/Contents/Developer"
fi

CODESIGN_KEYCHAIN=${CODESIGN_KEYCHAIN:-${HOME}/Library/Keychains/helpdesk-dev.keychain-db}
CODESIGN_KEYCHAIN_PASSWORD_FILE=${CODESIGN_KEYCHAIN_PASSWORD_FILE:-${HOME}/.local/share/helpdesk-client-dev-cert/keychain.pass}

DEPLOYMENT_TARGET="10.13"
ARCHS="x86_64 arm64"
PKG_IDENTIFIER="com.github.ygini.hello-it"
PKG_BASENAME="TwinLakes-HelloIT"

function notarizePackage {
	NOTARIZATION_PAYLOAD_PATH="$1"

	echo "####### Notarize distribution package"
	xcrun notarytool submit "${NOTARIZATION_PAYLOAD_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
	if [ $? -ne 0 ]; then
		echo "#### NOTARIZATION ERROR ####"
		echo "Run: xcrun notarytool log <submission-id> --keychain-profile ${NOTARYTOOL_PROFILE}"
		exit $LINENO
	fi

	echo "### Staple the distribution package"
	xcrun stapler staple "${NOTARIZATION_PAYLOAD_PATH}" || exit $LINENO
}

# --- dedicated signing keychain -----------------------------------------------------------

ORIGINAL_KEYCHAIN_SEARCH_LIST=""

function restoreKeychainSearchList {
	if [ -n "${ORIGINAL_KEYCHAIN_SEARCH_LIST}" ]; then
		# `security list-keychains -s` appends "-db" to names that already end in ".keychain-db",
		# so restore with the base names.
		# shellcheck disable=SC2086
		security list-keychains -d user -s ${ORIGINAL_KEYCHAIN_SEARCH_LIST}
		ORIGINAL_KEYCHAIN_SEARCH_LIST=""
		echo "Keychain search list restored: $(security list-keychains -d user | tr -d '\n')"
	fi
}

function useDedicatedKeychain {
	if [ "${CODESIGN_KEYCHAIN}" == "none" ] || [ ! -f "${CODESIGN_KEYCHAIN}" ]; then
		echo "No dedicated signing keychain; using the default keychain search list"
		return
	fi
	if [ -f "${CODESIGN_KEYCHAIN_PASSWORD_FILE}" ]; then
		security unlock-keychain -p "$(cat "${CODESIGN_KEYCHAIN_PASSWORD_FILE}")" "${CODESIGN_KEYCHAIN}" || exit $LINENO
	fi
	ORIGINAL_KEYCHAIN_SEARCH_LIST=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' -e 's/\.keychain-db$/.keychain/' | tr '\n' ' ')
	trap restoreKeychainSearchList EXIT
	security list-keychains -d user -s "${CODESIGN_KEYCHAIN}" || exit $LINENO
	echo "Signing with keychain ${CODESIGN_KEYCHAIN} (search list narrowed for this build)"
}

cd "$(dirname "${BASH_SOURCE[0]}")"

GIT_ROOT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_DIR="${GIT_ROOT_DIR}/src"
BUILT_PRODUCTS_DIR="$(mktemp -d)"

cd "${GIT_ROOT_DIR}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ -n "${FORCE_CONFIGURATION}" ]; then
	CONFIGURATION="${FORCE_CONFIGURATION}"
elif [[ "$CURRENT_BRANCH" == "master" ]] || [[ "$CURRENT_BRANCH" == release* ]] || [[ "$CURRENT_BRANCH" == tlt/* ]]; then
	CONFIGURATION="Release"
else
	CONFIGURATION="Debug"
fi

UNCOMMITED_CHANGE=$(git status -s | wc -l | bc)

if [ -z "$FORCE_SKIP_REPO_STATE" ]; then
	if [ "$UNCOMMITED_CHANGE" -ne 0 ] && [ "$CONFIGURATION" == "Release" ]; then
		echo "You are on ${CURRENT_BRANCH} and there"
		echo "is some uncommited change to the repo."
		echo "Please, commit and try again, use a"
		echo "development branch, or set FORCE_SKIP_REPO_STATE=1."
		exit $LINENO
	fi
fi

MARKETING_VERSION=$(sed -n '/MARKETING_VERSION/{s/MARKETING_VERSION = //;s/;//;s/^[[:space:]]*//;p;q;}' "${PROJECT_DIR}/Hello-IT.xcconfig")

if [[ "$CURRENT_BRANCH" == release* ]]; then
	VERSION_FROM_BRANCH=$(echo "${CURRENT_BRANCH}" | awk -F'/' '{print $2}')
	if [[ "$VERSION_FROM_BRANCH" =~ ^[0-9]+\.[0-9]+ ]]; then
		MARKETING_VERSION=$VERSION_FROM_BRANCH
		sed -i '' "/MARKETING_VERSION/c\\
MARKETING_VERSION = ${MARKETING_VERSION}
" "${PROJECT_DIR}/Hello-IT.xcconfig"
		git add "${PROJECT_DIR}/Hello-IT.xcconfig"
		git commit -m "Update marketing version number according to release branch"
	fi
fi

"${PROJECT_DIR}/.BuildVersion.sh"

BASE_RELEASE_LOCATION="${GIT_ROOT_DIR}/package/build"
RELEASE_LOCATION="${BASE_RELEASE_LOCATION}/${MARKETING_VERSION}-${CONFIGURATION}"
RELEASE_PRODUCT_LOCATION="${RELEASE_LOCATION}/Products"
RELEASE_DSYM_LOCATION="${RELEASE_LOCATION}/dSYM"
PKG_PATH="${RELEASE_LOCATION}/${PKG_BASENAME}-${MARKETING_VERSION}-${CONFIGURATION}.pkg"

PKG_ROOT="$(mktemp -d)"

if [[ -d "${RELEASE_LOCATION}" ]]; then
	echo "Previous build found, cleaning all related files"
	rm -rf "${RELEASE_LOCATION}"
fi

mkdir -p "${BUILT_PRODUCTS_DIR}/dSYM"
mkdir -p "${BUILT_PRODUCTS_DIR}/Products"
mkdir -p "${RELEASE_PRODUCT_LOCATION}"
mkdir -p "${RELEASE_DSYM_LOCATION}"

echo "Xcode: ${DEVELOPER_DIR:-$(xcode-select -p)}"
echo "Project location: ${PROJECT_DIR}"
echo "Temporary build dir: ${BUILT_PRODUCTS_DIR}"
echo "Release location: ${RELEASE_LOCATION}"
echo "Configuration: ${CONFIGURATION}, version ${MARKETING_VERSION}, archs ${ARCHS}, floor ${DEPLOYMENT_TARGET}"
echo "App identity: ${DEVELOPER_ID_APP}"
echo "Installer identity: ${DEVELOPER_ID_INSTALLER:-(none, pkg will be unsigned)}"

useDedicatedKeychain

echo "####### Build project"
echo "### Start building Hello IT"

# The scheme (not -target) is required so HITDevKit and the plugins build first.
xcodebuild \
	-project "${PROJECT_DIR}/Hello IT.xcodeproj" \
	-scheme "Hello IT" \
	-configuration "${CONFIGURATION}" \
	-derivedDataPath "${BUILT_PRODUCTS_DIR}/DerivedData" \
	-quiet \
	ARCHS="${ARCHS}" \
	ONLY_ACTIVE_ARCH=NO \
	MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="${DEVELOPER_ID_APP}" \
	DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
	CONFIGURATION_BUILD_DIR="${BUILT_PRODUCTS_DIR}/Products" \
	DWARF_DSYM_FOLDER_PATH="${BUILT_PRODUCTS_DIR}/dSYM" \
	OTHER_CODE_SIGN_FLAGS="--timestamp"

if [[ $? != 0 ]]; then
	echo "Building failed"
	exit 1
fi

cp -a "${BUILT_PRODUCTS_DIR}/Products/Hello IT.app" "${RELEASE_PRODUCT_LOCATION}"

# xcodebuild signs every target (plugins, framework, app) with its own entitlements and
# the hardened runtime. Re-signing with --deep --force here (as upstream did) would strip
# the app's entitlements, including disable-library-validation, which the plugins need.
codesign --verify --deep --strict --verbose=2 "${RELEASE_PRODUCT_LOCATION}/Hello IT.app" || exit $LINENO
if ! codesign -d --entitlements :- "${RELEASE_PRODUCT_LOCATION}/Hello IT.app" 2>/dev/null | grep -q 'disable-library-validation'; then
	echo "App is missing the disable-library-validation entitlement; plugins would not load"
	exit $LINENO
fi

echo ""
echo "### Built app"
lipo -info "${RELEASE_PRODUCT_LOCATION}/Hello IT.app/Contents/MacOS/Hello IT"
echo "LSMinimumSystemVersion: $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${RELEASE_PRODUCT_LOCATION}/Hello IT.app/Contents/Info.plist")"
echo "CFBundleShortVersionString: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${RELEASE_PRODUCT_LOCATION}/Hello IT.app/Contents/Info.plist")"
echo ""

cp -a "${BUILT_PRODUCTS_DIR}/dSYM/." "${RELEASE_DSYM_LOCATION}" 2>/dev/null

echo "####### Create package from build"

SUPPORT_DIR="${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it"

mkdir -p "${PKG_ROOT}/Applications/Utilities"
cp -a "${RELEASE_PRODUCT_LOCATION}/Hello IT.app" "${PKG_ROOT}/Applications/Utilities"

mkdir -p "${SUPPORT_DIR}/CustomImageForItem"
mkdir -p "${SUPPORT_DIR}/CustomStatusBarIcon"
cp -a "${PROJECT_DIR}/Plugins/ScriptedItem/CustomScripts" "${SUPPORT_DIR}"
# Twin Lakes scripts live next to the stock ones (plan F6)
cp -a "${GIT_ROOT_DIR}"/deploy/scripts/*.sh "${SUPPORT_DIR}/CustomScripts/"
cp -a "${GIT_ROOT_DIR}/deploy/uninstall.sh" "${SUPPORT_DIR}/uninstall.sh"
chmod 755 "${SUPPORT_DIR}"/CustomScripts/*.sh "${SUPPORT_DIR}/uninstall.sh"

mkdir -p "${PKG_ROOT}/Library/LaunchAgents"
cp -a "${GIT_ROOT_DIR}/package/LaunchAgents/com.github.ygini.hello-it.plist" "${PKG_ROOT}/Library/LaunchAgents"
chmod 644 "${PKG_ROOT}/Library/LaunchAgents/com.github.ygini.hello-it.plist"

PBK_BUILD_COMPONENT="${BUILT_PRODUCTS_DIR}/components.plist"
pkgbuild --analyze --root "${PKG_ROOT}" "${PBK_BUILD_COMPONENT}"
/usr/libexec/PlistBuddy -c "Set 0:BundleIsRelocatable bool false" "${PBK_BUILD_COMPONENT}"

COMPONENT_PKG="${BUILT_PRODUCTS_DIR}/${PKG_BASENAME}-${MARKETING_VERSION}-component.pkg"

PKGBUILD_SIGN=()
PRODUCTBUILD_SIGN=()
if [ -n "${DEVELOPER_ID_INSTALLER}" ]; then
	PKGBUILD_SIGN=(--sign "${DEVELOPER_ID_INSTALLER}" --timestamp)
	PRODUCTBUILD_SIGN=(--sign "${DEVELOPER_ID_INSTALLER}" --timestamp)
fi

pkgbuild \
	--component-plist "${PBK_BUILD_COMPONENT}" \
	--root "${PKG_ROOT}" \
	--ownership recommended \
	--scripts "${GIT_ROOT_DIR}/deploy/pkg_scripts" \
	--identifier "${PKG_IDENTIFIER}" \
	--version "${MARKETING_VERSION}" \
	--install-location "/" \
	"${PKGBUILD_SIGN[@]}" \
	"${COMPONENT_PKG}" || exit $LINENO

productbuild \
	--product "${GIT_ROOT_DIR}/package/requirements.plist" \
	--identifier "${PKG_IDENTIFIER}" \
	--version "${MARKETING_VERSION}" \
	--package "${COMPONENT_PKG}" \
	"${PRODUCTBUILD_SIGN[@]}" \
	"${PKG_PATH}"

if [[ $? != 0 ]]; then
	echo "Package creation failed"
	exit 1
fi

if [ -n "${DEVELOPER_ID_INSTALLER}" ] && [ -n "${NOTARYTOOL_PROFILE}" ]; then
	notarizePackage "${PKG_PATH}"
else
	echo "Skipping notarization (needs CUSTOM_DEVELOPER_ID_INSTALLER and NOTARYTOOL_PROFILE)"
fi

rm -rf "${PKG_ROOT}"

echo "####### Cleaning temporary files"
rm -rf "${BUILT_PRODUCTS_DIR}"
restoreKeychainSearchList

echo ""
echo "####### Done"
echo "Package: ${PKG_PATH}"
echo "SHA-256: $(shasum -a 256 "${PKG_PATH}" | awk '{print $1}')"

exit 0
