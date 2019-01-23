#!/bin/bash

SRC_DIR="$(dirname ${BASH_SOURCE[0]})"
PKG_VERSION="$(date +%Y.%m.%d).1"

PKG_ROOT=$(mktemp -d)
echo "####### Create package"

mkdir -p "${PKG_ROOT}/Library/Preferences"
cp -r "${SRC_DIR}/com.github.ygini.Hello-IT.plist" "${PKG_ROOT}/Library/Preferences"

pkgbuild --root "${PKG_ROOT}" --identifier "com.github.ygini.enrollme.hello-it.prefs" --scripts "${SRC_DIR}/pkg_scripts" --version "${PKG_VERSION}" "${SRC_DIR}/HelloIT-EnrollMe-Prefs-${PKG_VERSION}.pkg"

rm -rf "${PKG_ROOT}"

exit 0
