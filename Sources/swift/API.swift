
import Foundation

/// Main entry point of the library, used to control item download and get their playback URL.
public protocol ContentManager: class {
    
    /// Set download base path. Must be set before start(), otherwise has no effect.
    var storagePath: URL {get set}
    
    /// Set max concurrent downloads. This relates to download chunks, not DTGItems.
    /// Must be set before start() is called, otherwise has no effect.
    var maxConcurrentDownloads: Int {get set}
    
    /// Start the content manager. This also starts the playback server.
    func start()
    
    /// Stop the content manager, including the playback server.
    func stop()
    
    /// Resume downloading of items that were in progress when stop() was called.
    func resumeInterruptedItems()
    
    /// Return all items in the specified state.
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
    func addItem(id: String, url: URL) -> DTGItem?
    
    /// Load metadata for the given item id.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - callback: block that takes the updated item.
    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: (DTGItem?, DTGVideoTrack?, Error?) -> Void)
    
    /// Start or resume item download.
    func startItem(id: String)
    
    /// Pause downloading an item.
    func pauseItem(id: String)
    
    /// Remove an existing item from storage, deleting all related files.
    func removeItem(id: String)
    
    /// Get a playable URL for an item.
    /// - Returns: a playback URL, or nil.
    func itemPlaybackUrl(id: String) -> URL? 
    
    /// Delegate that will receive download events.
    var itemDelegate: DTGItemDelegate? {get set}
}

/// Delegate that will receive download events.
public protocol DTGItemDelegate: class {
    /// Item download has failed.
    func item(id: String, didFailWithError error: Error)
    
    /// Some data was downloaded for the item. 
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64)
    
    /// Item has changed state.
    func item(id: String, didMoveToState state: DTGItemState)
}

/// A downloadable item.
public protocol DTGItem {
    /// The item's unique id.
    var id: String {get}
    
    /// The items's remote URL.
    var remoteUrl: URL {get}
    
    /// The item's current state.
    var state: DTGItemState {get}
    
    /// Estimated size of the item.
    var estimatedSize: Int64? {get}
    
    /// Downloaded size in bytes.
    var downloadedSize: Int64? {get}
}

/// Information about a Video track.
public protocol DTGVideoTrack {
    /// Width in pixels.
    var width: Int? {get}
    
    /// Height in pixels.
    var height: Int? {get}
    
    /// Bitrate.
    var bitrate: Int {get}
}

/// Item state.
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
