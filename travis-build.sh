#!/bin/bash

set -eou pipefail

# Travis aborts the build if it doesn't get output for 10 minutes.
keepAlive() {
  while [ -f $1 ]
  do 
    sleep 10
    echo .
  done
}

testApp() {
  touch /tmp/DontPlay
  echo Building the test app
  cd Example
  pod install
  CODE=0
  xcodebuild test -workspace DownloadToGo.xcworkspace -scheme DownloadToGo-Example -sdk iphonesimulator ONLY_ACTIVE_ARCH=NO -destination 'platform=iOS Simulator,name=iPhone 11' | tee xcodebuild.log | xcpretty -r html || CODE=$?
  export CODE
  env > env.txt
  zip --junk-paths data.zip xcodebuild.log build/reports/tests.html env.txt
  curl "$ARTIFACT_UPLOAD_URL" -Fdata.zip=@data.zip -FResult=$CODE
  [ $CODE == 0 ]
}

libLint() {
  echo Linting the pod
  pod lib lint --allow-warnings
}


FLAG=$(mktemp)

if [ -n "$TRAVIS_TAG" ] || [ "$TRAVIS_EVENT_TYPE" == "cron" ]; then
  keepAlive $FLAG &
  libLint
else
  testApp
fi

rm $FLAG  # stop keepAlive
