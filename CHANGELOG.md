# Next

Allow sample app to handle OTT assets from JSON.

# 3.9.0

## Changes
- Fix downloading of Audio-only assets (#44). This feature was accidentally broken in #35.
- Send a user agent header that looks like a browser (#42). This is important for certain analytics tools.

## Breaking change
- The enums VideoCodec and AudioCodec in DTGSelectionOptions have been merged to a single enum, TrackCodec.
