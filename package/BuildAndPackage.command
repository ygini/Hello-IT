#!/bin/bash

CONFIGURATION="Release"

DEFAULT_DEVELOPER_ID_INSTALLER="Developer ID Installer: Yoann GINI (CRXPBZF3N4)"
DEVELOPER_ID_INSTALLER=${CUSTOM_DEVELOPER_ID_INSTALLER:-${DEFAULT_DEVELOPER_ID_INSTALLER}}

echo "Packaging will use ${DEVELOPER_ID_INSTALLER}"

GIT_ROOT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_DIR="${GIT_ROOT_DIR}/src"
BUILT_PRODUCTS_DIR="$(mktemp -d)"

cd "${GIT_ROOT_DIR}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ "$CURRENT_BRANCH" == "master" ]]
then
	CONFIGURATION="Release"
elif [[ "$CURRENT_BRANCH" == release* ]]
then
        CONFIGURATION="Release"
else
        CONFIGURATION="Debug"
fi

UNCOMMITED_CHANGE=$(git status -s | wc -l | bc)

if [ $UNCOMMITED_CHANGE -ne 0 ] && [ "$CONFIGURATION" == "Release" ]
then
	echo "Your are on ${CURRENT_BRANCH} and there"
	echo "is some uncommited change to the repo."
	echo "Please, commit and try again or use"
	echo "a development branch."
	exit 1
fi

PKG_VERSION=$(/usr/libexec/PlistBuddy -c "print CFBundleShortVersionString" "${PROJECT_DIR}/Hello IT/Info.plist")

if [[ "$CURRENT_BRANCH" == release* ]]
then
        CONFIGURATION="Release"
        VERSION_FROM_BRANCH=$(echo "${CURRENT_BRANCH}" | awk -F'/' '{print $2}')
        if [[ "$VERSION_FROM_BRANCH" =~ ^[0-9]+\.[0-9]+ ]]
        then
                PKG_VERSION=$VERSION_FROM_BRANCH
                /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $PKG_VERSION" "${PROJECT_DIR}/Hello IT/Info.plist"
                git add "${PROJECT_DIR}/Hello IT/Info.plist"
		git commit -m "Update app version number according to release branch" 
        fi
fi

BASE_RELEASE_LOCATION="${GIT_ROOT_DIR}/package/build"
RELEASE_LOCATION="${BASE_RELEASE_LOCATION}/${PKG_VERSION}-${CONFIGURATION}"
RELEASE_PRODUCT_LOCATION="${RELEASE_LOCATION}/Products"
RELEASE_DSYM_LOCATION="${RELEASE_LOCATION}/dSYM"

PKG_ROOT="$(mktemp -d)"

mkdir -p "${BUILT_PRODUCTS_DIR}/dSYM"
mkdir -p "${BUILT_PRODUCTS_DIR}/Products"
mkdir -p "${RELEASE_PRODUCT_LOCATION}"
mkdir -p "${RELEASE_DSYM_LOCATION}"

echo "Project location: ${PROJECT_DIR}"
echo "Temporary build dir: ${BUILT_PRODUCTS_DIR}"
echo "Release location: ${RELEASE_LOCATION}"

echo "####### Build project"

echo "### Start building Hello IT"

xcodebuild -quiet -project "${PROJECT_DIR}/Hello IT.xcodeproj" -configuration ${CONFIGURATION} -target "Hello IT" CONFIGURATION_TEMP_DIR="${BUILT_PRODUCTS_DIR}/Intermediates" CONFIGURATION_BUILD_DIR="${BUILT_PRODUCTS_DIR}/Products" DWARF_DSYM_FOLDER_PATH="${BUILT_PRODUCTS_DIR}/dSYM"

cp -r "${BUILT_PRODUCTS_DIR}/Products/Hello IT.app" "${RELEASE_PRODUCT_LOCATION}"

echo ""
echo ""


cp -r "${BUILT_PRODUCTS_DIR}/dSYM" "${RELEASE_DSYM_LOCATION}"

echo "####### Create package from build"

mkdir -p "${PKG_ROOT}//Applications/Utilities"
cp -r "${RELEASE_PRODUCT_LOCATION}/Hello IT.app" "${PKG_ROOT}/Applications/Utilities"

mkdir -p "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem"
mkdir -p "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it/CustomStatusBarIcon"
cp -r "${PROJECT_DIR}/Plugins/ScriptedItem/CustomScripts" "${PKG_ROOT}/Library/Application Support/com.github.ygini.hello-it"

mkdir -p "${PKG_ROOT}/Library/LaunchAgents"
cp -r "${GIT_ROOT_DIR}/package/LaunchAgents/com.github.ygini.hello-it.plist" "${PKG_ROOT}/Library/LaunchAgents"

#sudo chown -R root:wheel "${PKG_ROOT}"

pkgbuild --sign "${DEVELOPER_ID_INSTALLER}" --root "${PKG_ROOT}" --scripts "${GIT_ROOT_DIR}/package/pkg_scripts" --identifier "com.github.ygini.hello-it" --version "${PKG_VERSION}" "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}.pkg"

rm -rf "${PKG_ROOT}"

echo "####### Cleaning temporary files"

rm -rf "${BUILT_PRODUCTS_DIR}"

exit 0
