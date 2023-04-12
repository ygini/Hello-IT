#!/bin/bash

# Use the CUSTOM_ prefixed values to overload the default value of this script.
#  CUSTOM_DEVELOPER_ID_INSTALLER for the Installer certificate name used by codesign
#  CUSTOM_DEVELOPER_ID_APP for the App certificate name used by codesign
#  CUSTOM_NOTARIZATION_KEYCHAIN_PROFILE for the stored credential needed for notarytool
# Use xcrun notarytool store-credentials to store a credentials for notarization

DEFAULT_DEVELOPER_ID_INSTALLER="Developer ID Installer: Yoann GINI (CRXPBZF3N4)"
DEFAULT_DEVELOPER_ID_APP="Developer ID Application: Yoann GINI (CRXPBZF3N4)"
DEFAULT_NOTARIZATION_KEYCHAIN_PROFILE="yoann.gini@gmail.com"

DEVELOPER_ID_INSTALLER=${CUSTOM_DEVELOPER_ID_INSTALLER:-${DEFAULT_DEVELOPER_ID_INSTALLER}}
DEVELOPER_ID_APP=${CUSTOM_DEVELOPER_ID_APP:-${DEFAULT_DEVELOPER_ID_APP}}
NOTARIZATION_KEYCHAIN_PROFILE=${CUSTOM_NOTARIZATION_KEYCHAIN_PROFILE:-${DEFAULT_NOTARIZATION_KEYCHAIN_PROFILE}}

echo "Packaging will use ${DEVELOPER_ID_INSTALLER}"
echo "Apps will use ${DEFAULT_DEVELOPER_ID_APP}"
echo "Notarization will use ${NOTARIZATION_KEYCHAIN_PROFILE}"

cd "$(dirname "${BASH_SOURCE[0]}")"

GIT_ROOT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_DIR="${GIT_ROOT_DIR}/src"
BUILT_PRODUCTS_DIR="$(mktemp -d)"

cd "${GIT_ROOT_DIR}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

CONFIGURATION="Debug"

if [[ "$CURRENT_BRANCH" == "master" ]]
then
	CONFIGURATION="Release"
elif [[ "$CURRENT_BRANCH" == release* ]]
then
        CONFIGURATION="Release"
fi

MARKETING_VERSION=$(sed -n '/MARKETING_VERSION/{s/MARKETING_VERSION = //;s/;//;s/^[[:space:]]*//;p;q;}' "${PROJECT_DIR}/Hello-IT.xcconfig")

UNCOMMITED_CHANGE=$(git status -s | wc -l | bc)

if [ -z $FORCE_SKIP_REPO_STATE ]
then
	if [ $UNCOMMITED_CHANGE -ne 0 ] && [ "$CONFIGURATION" == "Release" ]
	then
		echo "Your are on ${CURRENT_BRANCH} and there"
		echo "is some uncommited change to the repo."
		echo "Please, commit and try again or use"
		echo "a development branch."
		exit $LINENO
	fi
	
	if [[ "$CURRENT_BRANCH" == release* ]]
	then
			CONFIGURATION="Release"
			VERSION_FROM_BRANCH=$(echo "${CURRENT_BRANCH}" | awk -F'/' '{print $2}')
			if [[ "$VERSION_FROM_BRANCH" =~ ^[0-9]+\.[0-9]+ ]]
			then
					MARKETING_VERSION=$VERSION_FROM_BRANCH
			sed -i '' "/MARKETING_VERSION/c\\
	MARKETING_VERSION = ${MARKETING_VERSION}
	" "${PROJECT_DIR}/Hello-IT.xcconfig"
					git add "${PROJECT_DIR}/Hello-IT.xcconfig"
			git commit -m "Update marketing version number according to release branch" 
			fi
	fi
fi

"${PROJECT_DIR}/.BuildVersion.sh"

BASE_RELEASE_LOCATION="${GIT_ROOT_DIR}/package/build"
RELEASE_LOCATION="${BASE_RELEASE_LOCATION}/${MARKETING_VERSION}-${CONFIGURATION}"
RELEASE_PRODUCT_LOCATION="${RELEASE_LOCATION}/Products"
RELEASE_DSYM_LOCATION="${RELEASE_LOCATION}/dSYM"

PKG_ROOT="$(mktemp -d)"

if [[ -d "${RELEASE_LOCATION}" ]]
then
	echo "Previous build found, cleaning all related files"
	rm -rf "${RELEASE_LOCATION}"
fi

mkdir -p "${BUILT_PRODUCTS_DIR}/dSYM"
mkdir -p "${BUILT_PRODUCTS_DIR}/Products"
mkdir -p "${RELEASE_PRODUCT_LOCATION}"
mkdir -p "${RELEASE_DSYM_LOCATION}"

echo "Project location: ${PROJECT_DIR}"
echo "Temporary build dir: ${BUILT_PRODUCTS_DIR}"
echo "Release location: ${RELEASE_LOCATION}"

echo "####### Build project"

echo "### Start building Hello IT SDK"
xcodebuild -UseModernBuildSystem=NO -arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO -quiet -project "${PROJECT_DIR}/HITDevKit/HITDevKit.xcodeproj" -configuration ${CONFIGURATION} -target "HITDevKit" CONFIGURATION_TEMP_DIR="${BUILT_PRODUCTS_DIR}/Intermediates" CONFIGURATION_BUILD_DIR="${BUILT_PRODUCTS_DIR}/Products" DWARF_DSYM_FOLDER_PATH="${BUILT_PRODUCTS_DIR}/dSYM" OTHER_CODE_SIGN_FLAGS="--timestamp"
if [[ $? != 0 ]]; then
    echo "Building failed"
    exit 1
fi

echo "### Start building Hello IT app and plugins"
xcodebuild -UseModernBuildSystem=NO -arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO -quiet -project "${PROJECT_DIR}/Hello IT.xcodeproj" -configuration ${CONFIGURATION} -target "Hello IT" CONFIGURATION_TEMP_DIR="${BUILT_PRODUCTS_DIR}/Intermediates" CONFIGURATION_BUILD_DIR="${BUILT_PRODUCTS_DIR}/Products" DWARF_DSYM_FOLDER_PATH="${BUILT_PRODUCTS_DIR}/dSYM" OTHER_CODE_SIGN_FLAGS="--timestamp"

if [[ $? != 0 ]]; then
    echo "Building failed"
    exit 1
fi

cp -a "${BUILT_PRODUCTS_DIR}/Products/Hello IT.app" "${RELEASE_PRODUCT_LOCATION}"

codesign --deep --force --verbose --timestamp --options runtime --sign "${DEVELOPER_ID_APP}" "${RELEASE_PRODUCT_LOCATION}/Hello IT.app"

if [[ $? != 0 ]]; then
    echo "Code signature failed"
    exit 1
fi

echo ""
echo ""


cp -a "${BUILT_PRODUCTS_DIR}/dSYM" "${RELEASE_DSYM_LOCATION}"

echo "####### Create package from build"

mkdir -p "${PKG_ROOT}/Applications/Utilities"
cp -a "${RELEASE_PRODUCT_LOCATION}/Hello IT.app" "${PKG_ROOT}/Applications/Utilities"

mkdir -p "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem"
mkdir -p "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it/CustomStatusBarIcon"
cp -a "${PROJECT_DIR}/Plugins/ScriptedItem/CustomScripts" "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it"

mkdir -p "${PKG_ROOT}/Library/LaunchAgents"
cp -a "${GIT_ROOT_DIR}/package/LaunchAgents/com.github.ygini.hello-it.plist" "${PKG_ROOT}/Library/LaunchAgents"

PBK_BUILD_COMPONENT="${BUILT_PRODUCTS_DIR}/components.plist"
pkgbuild --analyze --root "${PKG_ROOT}" "${PBK_BUILD_COMPONENT}"

/usr/libexec/PlistBuddy -c "Set 0:BundleIsRelocatable bool false" "${PBK_BUILD_COMPONENT}"

pkgbuild --component-plist "${PBK_BUILD_COMPONENT}" --sign "${DEVELOPER_ID_INSTALLER}" --root "${PKG_ROOT}" --scripts "${GIT_ROOT_DIR}/package/pkg_scripts" --identifier "com.github.ygini.hello-it" --version "${MARKETING_VERSION}" "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}.pkg"

productbuild --product "${GIT_ROOT_DIR}/package/requirements.plist" --sign "${DEVELOPER_ID_INSTALLER}" --version "${MARKETING_VERSION}" --package "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}.pkg" "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}-Distribution.pkg"

if [[ $? != 0 ]]; then
    echo "Package creation failed"
    exit 1
fi

rm "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}.pkg"

xcrun notarytool submit "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}-Distribution.pkg" --keychain-profile "${NOTARIZATION_KEYCHAIN_PROFILE}" --wait

if [[ $? != 0 ]]; then
	echo "Notarization failed, run the following command with the appropriate UUID"
	echo "  xcrun notarytool log <UUID> --keychain-profile \"${NOTARIZATION_KEYCHAIN_PROFILE}\""
	exit 1	
fi

xcrun stapler staple "${RELEASE_LOCATION}/Hello-IT-${MARKETING_VERSION}-${CONFIGURATION}-Distribution.pkg"
	
echo "####### Cleaning temporary files"

rm -rf "${PKG_ROOT}"
rm -rf "${BUILT_PRODUCTS_DIR}"

exit 0
