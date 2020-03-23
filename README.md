# Download To Go
Download-to-Go (DTG) for iOS. 

Used to download Kaltura HLS streams for offline playback. 

## M3U8Kit
DTG uses an external HLS parser, M3U8Kit. There's a small addition we made to that library, and it's not yet merged ([GitHub PR](https://github.com/M3U8Kit/M3U8Parser/pull/22)).
As a workaround, the app needs to directly point to Kaltura's fork of the pod:

    pod 'M3U8Kit', :git => 'https://github.com/kaltura/M3U8Paser', :tag => 'k0.3.2'

This tag is based on the official v0.3.2, with just this addition (see the linked PR).

## Documentation
Please see our [documentation](https://kaltura.github.io/playkit/guide/ios/dtg/) for usage and info.

## License and Copyright Information
All code in this project is released under the [AGPLv3 license](http://www.gnu.org/licenses/agpl-3.0.html) unless a different license for a particular library is specified in the applicable library path.   

Copyright © Kaltura Inc. All rights reserved.   
Authors and contributors: See [GitHub contributors list](https://github.com/kaltura/playkit-dtg-ios/graphs/contributors).
