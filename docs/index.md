---
title: Download-to-Go for iOS
---

# Download-to-Go for iOS

Download to Go (DTG) is an iOS library that facilitates the download of HLS video assets.

## Supported Features 
- Downloading Kaltura HLS assets (Clear only)
- Background downloading.
- Resuming interrupted/paused downloads.

## Known Limitations
- No track selection
- Can't play downloaded assets in background

## Installation

### [CocoaPods][cocoapods]

Add this to your podfile:
```ruby
pod 'DownloadToGo'
```

## Overview

### Simple Flow:

![](Resources/simple-flow-uml.png)

>Note: There is also `Removed` state which is not displayed here. `Removed` is a temporary state indicated an item was removed (can be considered as an event). You can remove an item from all states. 

### Download Sequence:

![](Resources/download-sequence.png)

### Simple Playing Sequence (Using PlayKit Player):

![](Resources/playing-sequence.png)

## Usage

To use the DTG make sure to import in each source file:
```swift
import DownloadToGo
```

The following classes/interfaces are the public API of the library:
* `ContentManager` - Use this class to interact with the library.
* `DTGContentManager` - This is the main api you will use to interact with the library.
* `ContentManagerDelegate` - Delegate calls available to observe.
* `DTGItem` - Represent a single download item.
* `DTGItemState` - The state of a download item.


[cocoapods]: https://cocoapods.org/
