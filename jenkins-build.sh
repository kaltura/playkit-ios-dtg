#!/bin/bash

pushd Example
pod install

xcodebuild test -derivedDataPath build -workspace DownloadToGo.xcworkspace -scheme DownloadToGo-Example -sdk iphonesimulator \
	ONLY_ACTIVE_ARCH=NO -destination 'platform=iOS Simulator,name=iPhone X' | tee xcodebuild.log | xcpretty -r html

popd
mkdir out
mv Example/build/reports/tests.html Example/xcodebuild.log out

