#!/bin/bash

set -eou pipefail

# Login to cocoapods trunk.
login() {
cat << EOF > ~/.netrc
machine trunk.cocoapods.org
  login $COCOAPODS_USERNAME
  password $COCOAPODS_PASSWORD
EOF

chmod 0600 ~/.netrc
}

# Travis aborts the build if it doesn't get output for 10 minutes.
keepAlive() {
  while [ -f $1 ]
  do 
    sleep 10
    echo .
  done
}

trunkPush() {
  echo Pushing to Cocoapods trunk
  login
  pod trunk push --allow-warnings
}

justBuild() {
  echo Building the test app
  cd Example
  pod install
  xcodebuild build -workspace DownloadToGo.xcworkspace -scheme DownloadToGo-Example -sdk iphonesimulator ONLY_ACTIVE_ARCH=NO | xcpretty
}

libLint() {
  echo Linting the pod
  pod lib lint --allow-warnings
}


FLAG=$(mktemp)
keepAlive $FLAG &

if [[ $TRAVIS_TAG =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # If we're building a release tag (v1.2.3) push to cocoapods
  trunkPush
elif [ "$TRAVIS_EVENT_TYPE" == "cron" ]; then
  # A cron build should do a full build (daily)
  libLint
else
  # Just build the test app (for every push and PR)
  justBuild
fi

rm $FLAG  # stop keepAlive
