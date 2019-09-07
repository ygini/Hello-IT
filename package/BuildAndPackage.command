#!/bin/bash

CONFIGURATION="Release"

DEFAULT_DEVELOPER_ID_INSTALLER="Developer ID Installer: Yoann GINI (CRXPBZF3N4)"
DEVELOPER_ID_INSTALLER=${CUSTOM_DEVELOPER_ID_INSTALLER:-${DEFAULT_DEVELOPER_ID_INSTALLER}}

NOTARIZATION_DEFAULT_DEVELOPER_ID_LOGIN="yoann.gini@gmail.com"
NOTARIZATION_DEVELOPER_ID_LOGIN=${NOTARIZATION_CUSTOM_DEVELOPER_ID_LOGIN:-${NOTARIZATION_DEFAULT_DEVELOPER_ID_LOGIN}}

# Use app-specific password, you can create one at appleid.apple.com
NOTARIZATION_DEFAULT_DEVELOPER_ID_PASSWORD="@keychain:altool-credentials"
NOTARIZATION_DEVELOPER_ID_PASSWORD=${NOTARIZATION_CUSTOM_DEVELOPER_ID_PASSWORD:-${NOTARIZATION_DEFAULT_DEVELOPER_ID_PASSWORD}}

function showNotarizationErrors {
	NOTARIZATION_FILE="$1"
	i=0
	while true
	do
		NOTARIZATION_ERROR_MESSAGE=$(/usr/libexec/PlistBuddy -c "Print :product-errors:$i:message" "${NOTARIZATION_FILE}" 2>/dev/null)
		if [ $? -ne 0 ]
		then
			break
		fi
		
		echo "#### NOTARIZATION ERROR ####"
		echo "Last status: ${NOTARIZATION_STATUS}"
		echo "${NOTARIZATION_ERROR_MESSAGE}"
		
		i=$(($i + 1))
	done
}

function notarizePayloadWithBundleID {
	NOTARIZATION_PAYLOAD_PATH="$1"
	NOTARIZATION_BUNDLE_ID="$2"
	NOTARIZATION_TMP_DIR="$(mktemp -d)"
	
	echo "####### Notarize distribution package"

	echo "### Request notarization"
	xcrun altool --notarize-app --primary-bundle-id "${NOTARIZATION_BUNDLE_ID}" -u "${NOTARIZATION_DEVELOPER_ID_LOGIN}" -p "${NOTARIZATION_DEVELOPER_ID_PASSWORD}" -f "${NOTARIZATION_PAYLOAD_PATH}" --output-format xml > "${NOTARIZATION_TMP_DIR}/notarize-app.plist"
	
	if [ $? -ne 0 ]
	then
		showNotarizationErrors "${NOTARIZATION_TMP_DIR}/notarize-app.plist"
		exit 1
	fi
	
	NOTARIZATION_UUID=$(/usr/libexec/PlistBuddy -c "Print :notarization-upload:RequestUUID" "${NOTARIZATION_TMP_DIR}/notarize-app.plist" 2>/dev/null)
	
	if [ -z "{NOTARIZATION_UUID}" ]
	then
		echo "#### NOTARIZATION ERROR ####"
		echo "No UUID returned"
		showNotarizationErrors "${NOTARIZATION_TMP_DIR}/notarize-app.plist"
		exit 2
	fi
	
	NOTARIZATION_STATUS="in progress"
	echo "### Wait for notarization"
	while [ "${NOTARIZATION_STATUS}" == "in progress" ]
	do
		xcrun altool --notarization-info "${NOTARIZATION_UUID}" -u "${NOTARIZATION_DEVELOPER_ID_LOGIN}" -p "${NOTARIZATION_DEVELOPER_ID_PASSWORD}" --output-format xml > "${NOTARIZATION_TMP_DIR}/notarization-info.plist"
		NOTARIZATION_STATUS=$(/usr/libexec/PlistBuddy -c "Print :notarization-info:Status" "${NOTARIZATION_TMP_DIR}/notarization-info.plist" 2>/dev/null)
		
		if [ "${NOTARIZATION_STATUS}" == "in progress" ]
		then
				echo -n "."
				sleep 5
		fi	
	done
	
	echo ""
	
	NOTARIZATION_LOG_URL=$(/usr/libexec/PlistBuddy -c "Print :notarization-info:LogFileURL" "${NOTARIZATION_TMP_DIR}/notarization-info.plist" 2>/dev/null)
	
	if [ -z "$(command -v jq)" ]
	then
		echo "Notarization logs available here: ${NOTARIZATION_LOG_URL}"
	else
		curl "${NOTARIZATION_LOG_URL}" > "${NOTARIZATION_TMP_DIR}/notarization-logs.json"
		
		while read issue
		do
			NOTARIZATION_LOG_MESSAGE=$(echo "$issue" | jq ".message" )
			NOTARIZATION_LOG_SEVERITY=$(echo "$issue" | jq ".severity" )
			NOTARIZATION_LOG_PATH=$(echo "$issue" | jq ".path" )
			NOTARIZATION_LOG_DOCURL=$(echo "$issue" | jq ".docUrl" )
			
			echo "### Issue from notarization log:"
			echo "Severity: ${NOTARIZATION_LOG_SEVERITY}"
			echo "About: ${NOTARIZATION_LOG_PATH}"
			echo ""
			echo "${NOTARIZATION_LOG_MESSAGE}"
			echo ""
			if [ "${NOTARIZATION_LOG_DOCURL}" != "null" ]
			then
				echo "You should read ${NOTARIZATION_LOG_DOCURL}"
			fi
		done < <(cat "${NOTARIZATION_TMP_DIR}/notarization-logs.json" | jq -c ".issues[]")
	fi

	if [ "${NOTARIZATION_STATUS}" == "success" ]
	then
		cat "${NOTARIZATION_TMP_DIR}/notarization-info.plist"
		echo "### Staple the distribution package"
		xcrun stapler staple "${NOTARIZATION_PAYLOAD_PATH}"
	else 
		showNotarizationErrors "${NOTARIZATION_TMP_DIR}/notarization-info.plist"
		exit 3
	fi
	
	rm -rf "${NOTARIZATION_TMP_DIR}"
}

echo "Packaging will use ${DEVELOPER_ID_INSTALLER}"

cd "$(dirname "${BASH_SOURCE[0]}")"

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

if [ -z $FORCE_SKIP_REPO_STATE ]
then
	if [ $UNCOMMITED_CHANGE -ne 0 ] && [ "$CONFIGURATION" == "Release" ]
	then
		echo "Your are on ${CURRENT_BRANCH} and there"
		echo "is some uncommited change to the repo."
		echo "Please, commit and try again or use"
		echo "a development branch."
		exit 1
	fi
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

xcodebuild -UseModernBuildSystem=NO -quiet -project "${PROJECT_DIR}/Hello IT.xcodeproj" -configuration ${CONFIGURATION} -target "Hello IT" CONFIGURATION_TEMP_DIR="${BUILT_PRODUCTS_DIR}/Intermediates" CONFIGURATION_BUILD_DIR="${BUILT_PRODUCTS_DIR}/Products" DWARF_DSYM_FOLDER_PATH="${BUILT_PRODUCTS_DIR}/dSYM" OTHER_CODE_SIGN_FLAGS="--timestamp"

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

PBK_BUILD_COMPONENT="${BUILT_PRODUCTS_DIR}/components.plist"
pkgbuild --analyze --root "${PKG_ROOT}" "${PBK_BUILD_COMPONENT}"

/usr/libexec/PlistBuddy -c "Set 0:BundleIsRelocatable bool false" "${PBK_BUILD_COMPONENT}"
#/usr/libexec/PlistBuddy -c "Print" "${PBK_BUILD_COMPONENT}"
pkgbuild --component-plist "${PBK_BUILD_COMPONENT}" --sign "${DEVELOPER_ID_INSTALLER}" --root "${PKG_ROOT}" --scripts "${GIT_ROOT_DIR}/package/pkg_scripts" --identifier "com.github.ygini.hello-it" --version "${PKG_VERSION}" "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}.pkg"

productbuild --product "${GIT_ROOT_DIR}/package/requirements.plist" --sign "${DEVELOPER_ID_INSTALLER}" --version "${PKG_VERSION}" --package "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}.pkg" "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}-Distribution.pkg"

notarizePayloadWithBundleID "${RELEASE_LOCATION}/Hello-IT-${PKG_VERSION}-${CONFIGURATION}-Distribution.pkg" "com.github.ygini.hello-it"

rm -rf "${PKG_ROOT}"

echo "####### Cleaning temporary files"

rm -rf "${BUILT_PRODUCTS_DIR}"

exit 0
