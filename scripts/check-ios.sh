#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Mac에 Xcode를 설치하고 실행한 뒤 다시 실행해 주세요.' >&2
  exit 1
fi
mkdir -p build
xcrun swiftc BodybuildingPro/Models.swift Tests/main.swift -o build/model-checks
build/model-checks
xcodebuild -project BodybuildingPro.xcodeproj -scheme BodybuildingPro \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/build.log
