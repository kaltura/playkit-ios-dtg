# Download To Go
Download-to-Go (DTG) framework for iOS. 

Used to download Kaltura HLS streams for offline playback. 

## Documentation
Please see our [documentation](https://kaltura.github.io/playkit-dtg-ios) for usage and info.

## M3U8Kit
DTG uses an external HLS parser, M3U8Kit. Currently there's a bug in the latest version of this library. As a workaround, the app needs to 
directly point to Kaltura's fork of the pod:
    
    pod 'M3U8Kit', :git => 'https://github.com/kaltura/M3U8Paser', :tag => 'k0.2.2'


## License and Copyright Information
All code in this project is released under the [AGPLv3 license](http://www.gnu.org/licenses/agpl-3.0.html) unless a different license for a particular library is specified in the applicable library path.   

Copyright © Kaltura Inc. All rights reserved.   
Authors and contributors: See [GitHub contributors list](https://github.com/kaltura/playkit-dtg-ios/graphs/contributors).
