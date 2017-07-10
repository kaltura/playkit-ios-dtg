
import Foundation

/// Main entry point of the library, used to control item download and get their playback URL.
public protocol ContentManager: class {
    
    /// Set max concurrent downloads. This relates to download chunks, not DTGItems.
    /// Must be set before start() is called, otherwise has no effect.
    var maxConcurrentDownloads: Int {get set}
    
    /// Start the content manager. This also starts the playback server.
    func start()
    
    /// Stop the content manager, including the playback server.
    func stop()
    
    /// Resume downloading of items that were in progress when stop() was called.
    func resumeInterruptedItems()
    
    func itemsByState(_ state: DTGItemState) -> [DTGItem]
    
    /// Find an existing item.
    /// - Parameter id: the item's unique id.
    /// - Returns: an item, or nil if not found.
    func itemById(_ id: String) -> DTGItem?
    
    /// Add a new item.
    /// - Parameters:
    ///     - id: a unique id for the new item
    ///     - url: the remote URL of the item.
    /// - Returns: the newly allocated item or nil if already exists.
    func addItem(id: String, url: String) -> DTGItem?
    
    /// Load metadata for the given item id.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - callback: block that takes the updated item.
    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: DTGMetadataCallback)
    
    /// Start or resume item download.
    func startItem(id: String)
    
    /// Pause downloading an item.
    func pauseItem(id: String)
    
    /// Remove an existing item from storage, deleting all related files.
    func removeItem(id: String)
    
    /// Get a playable URL for an item.
    /// - Returns: a playback URL, or nil.
    func itemPlaybackUrl(id: String) -> URL? 
    
    /// Add error observer.
    func addErrorObserver(owner: Any, callback: @escaping DTGErrorCallback)
    /// Remove error observer.
    func removeErrorObserver(owner: Any)
    
    /// Add progress observer.
    func addProgressObserver(owner: Any, callback: @escaping DTGProgressCallback)
    /// Remove progress observer.
    func removeProgressObserver(owner: Any)
    
    /// Add state change observer.
    func addStateObserver(owner: Any, callback: @escaping DTGStateCallback)
    /// Remove state change observer.
    func removeStateObserver(owner: Any)
    
}

public typealias DTGErrorCallback = (DTGItem, Error)->Void
public typealias DTGProgressCallback = (DTGItem, Int64)->Void
public typealias DTGStateCallback = (DTGItem, DTGItemState)->Void
public typealias DTGMetadataCallback = (DTGItem?, DTGVideoTrack?, Error?) -> Void

/// A downloadable item.
public protocol DTGItem: class {
    /// The item's unique id.
    var id: String {get}
    
    /// The items's remote URL.
    var remoteUrl: String {get}
    
    /// The item's current state.
    var state: DTGItemState {get}
    
    /// Estimated size of the item.
    var estimatedSize: Int64? {get}
    
    /// Downloaded size in bytes.
    var downloadedSize: Int64? {get}
}

public protocol DTGTrack: class {
}

public enum DTGTrackType {
    case video
    case audio
    case text
}

public protocol DTGVideoTrack: DTGTrack {
    
    var width: Int? {get}
    
    var height: Int? {get}
    
    var bitrate: Int? {get}

    var codec: String? {get}
}

// NOTE: Not used in phase 1
public protocol DTGAudioTrack: DTGTrack {
    
    var bitrate: Int? {get}
    
    var codec: String? {get}
    
    var language: String? {get}
}

// NOTE: Not used in phase 1
public protocol DTGTextTrack: DTGTrack {
    
    var language: String? {get}
}

public enum DTGItemState: Int {
    /// Item was just added, no metadata is available except for the id and the URL.
    case new
    
    /// Item's metadata was loaded. Tracks information is available.
    case metadataLoaded
    
    /// Item download is in progress.
    case inProgress
    
    /// Item is paused by the app/user.
    case paused
    
    /// Item has finished downloading.
    case completed
    
    /// Item download has failed.
    case failed
    
    /// Item is removed. This is only a temporary state, as the item is actually removed.
    case removed
}
