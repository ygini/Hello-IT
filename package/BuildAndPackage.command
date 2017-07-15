#!/bin/bash

CONFIGURATION="Release"

GIT_ROOT_DIR="$(dirname $(dirname ${BASH_SOURCE[0]}))"
PROJECT_DIR="${GIT_ROOT_DIR}/src"
BUILT_PRODUCTS_DIR="$(mktemp -d)"

cd "${GIT_ROOT_DIR}"

PKG_VERSION=$(/usr/libexec/PlistBuddy -c "print CFBundleShortVersionString" "${PROJECT_DIR}/Hello IT/Info.plist")

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

pkgbuild --sign "Developer ID Installer: Yoann GINI (CRXPBZF3N4)" --root "${PKG_ROOT}" --scripts "${GIT_ROOT_DIR}/package/pkg_scripts" --identifier "com.github.ygini.hello-it" --version "${PKG_VERSION}" "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}.pkg"

rm -rf "${PKG_ROOT}"

echo "####### Cleaning temporary files"

rm -rf "${BUILT_PRODUCTS_DIR}"

exit 0
