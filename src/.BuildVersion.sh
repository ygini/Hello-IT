#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "GIT_BUILD_VERSION = $(git rev-list HEAD | wc -l)" > .BuildVersion.xcconfig

