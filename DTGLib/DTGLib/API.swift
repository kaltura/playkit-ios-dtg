
/// Main entry point of the library, used to control item download and get their playback URL.
public protocol ContentManager: class {
    
    /// Shared (singleton) ContentManager
    static var shared: ContentManager {get}
    
    /// Set max concurrent downloads. This relates to download chunks, not DTGItems.
    /// Must be set before start() is called, otherwise has no effect.
    var maxConcurrentDownloads: Int {get set}
    
    /// Start the content manager. This also starts the playback server.
    func start()
    
    /// Stop the content manager, including the playback server.
    func stop()
    
    /// Resume downloading of items that were in progress when stop() was called.
    func resumeInterruptedItems()
    
    
    /// Find an existing item.
    /// - Parameter id: the item's unique id.
    /// - Returns: an item, or nil if not found.
    func findItem(id: String) -> DTGItem?
    
    /// Add a new item.
    /// - Parameters:
    ///     - id: a unique id for the new item
    ///     - url: the remote URL of the item.
    /// - Returns: the newly allocated item or nil if already exists.
    func addItem(id: String, url: String) -> DTGItem?
    
    /// Load metadata for the given item id.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - callback: block that takes the updated item and a track selector. The application is expected
    ///                 to select tracks before the callback returns.
    func loadItemMetadata(id: String, callback: (DTGItem, DTGTrackSelector)->Void)
    
    /// Start downloading an item.
    /// - Parameters:
    ///     - id: the item's unique id.
    func startItem(id: String)
    
    /// Pause downloading an item.
    /// - Parameters:
    ///     - id: the item's unique id.
    func pauseItem(id: String)
    
    /// Remove an existing item from storage, deleting all related files.
    /// - Parameters:
    ///     - id: the item's unique id.
    func removeItem(id: String)
    
    /// Get a playable URL for an item.
    /// - Parameters:
    ///     - id: the item's unique id.
    /// - Returns: a playback URL, or nil.
    func itemPlaybackUrl(id: String) -> URL? 
    
}

/// Allows an application to select tracks for download. An instance of this class is
/// provided to the app when an item's metadata is loaded.
public protocol DTGTrackSelector: class {
    /// Get the available tracks of a given type.
    /// - Parameter type: track type.
    /// - Returns: an array with tracks of the requested type.
    func availableTracks(type: DTGTrackType) -> [DTGTrack]
    
    /// Add list of tracks to download.
    /// - Parameter tracks: the tracks to add to the download.
    func addTracks(tracks: [DTGTrack])
    
    /// Select the default tracks. This discards of any added tracks.
    func selectDefaults()
}

public extension DTGTrackSelector {
    /// Add all tracks of the given type.
    /// - Note: shouldn't be called with the `video` type.
    func addAllTracks(type: DTGTrackType) {
        let tracks = availableTracks(type: type)
        addTracks(tracks: tracks)
    }
}

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
    
    /// Get the downloaded tracks of a given type.
    /// - Parameter type: track type.
    /// - Returns: an array with the downloaded tracks.
    func downloadedTracks(type: DTGTrackType) -> [DTGTrack]
}

public protocol DTGTrack: class {
}

public protocol DTGTextTrack: class {
    
    var language: String? {get}
}

public protocol DTGVideoTrack: class {
    
    var width: Int? {get}
    
    var height: Int? {get}
    
    var bitrate: Int? {get}

    var codec: String? {get}
}

public protocol DTGAudioTrack: class {
    
    var bitrate: Int? {get}
    
    var codec: String? {get}
    
    var language: String? {get}
}

public enum DTGTrackType {
    case video
    case audio
    case text
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
}
