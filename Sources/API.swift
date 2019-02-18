// ===================================================================================================
// Copyright (C) 2017 Kaltura Inc.
//
// Licensed under the AGPLv3 license, unless a different license for a 
// particular library is specified in the applicable library path.
//
// You may obtain a copy of the License at
// https://www.gnu.org/licenses/agpl-3.0.html
// ===================================================================================================


import Foundation
import XCGLogger

/// Main entry point of the library, used to control item download and get their playback URL.
public protocol DTGContentManager: class {
    
    /// The storage path for directories and files.
    var storagePath: URL { get }
    
    /// Delegate that will receive download events.
    var delegate: ContentManagerDelegate? { get set }
    
    /// set log level for viewing logs.
    func setLogLevel(_ logLevel: LogLevel)
    
    /// Start the content manager. This also starts the playback server.
    func start(completionHandler: (() -> Void)?) throws
    
    /// Stop the content manager, including the playback server.
    func stop()
    
    /// Return all items in the specified state.
    func itemsByState(_ state: DTGItemState) throws -> [DTGItem]
    
    /// Find an existing item.
    /// - Parameter id: the item's unique id.
    /// - Returns: an item, or nil if not found.
    func itemById(_ id: String) throws -> DTGItem?
    
    /// Add a new item.
    /// - Parameters:
    ///     - id: a unique id for the new item
    ///     - url: the remote URL of the item.
    /// - Returns: the newly allocated item or nil if already exists.
    func addItem(id: String, url: URL) throws -> DTGItem?
    
    /// Load metadata for the given item id.
    /// - Attention:
    /// This method executes on the thread it is called and takes time to finish,
    /// the **best practice is to call this method from a background queue**.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - callback: block that takes the updated item.
    /// - Throws: DTGError.itemNotFound
    func loadItemMetadata(id: String, preferredVideoBitrate: Int?) throws
    
    func loadItemMetadata(id: String, options: DTGSelectionOptions?) throws
    
    /// Start or resume item download.
    /// - Throws: DTGError.itemNotFound
    func startItem(id: String) throws
    
    /// Start items download in specified states.
    /// can be used to resume inProgress (after force quit) / interrupted / paused items, can use multiple selection or just one.
    ///
    /// ````
    /// try startItems(inStates: .inProgress)
    /// // or like this:
    /// try startItems(inStates: .inProgress, .paused)
    /// ````
    ///
    /// - Parameter states: The states to start.
    func startItems(inStates states: DTGItemStartableState...) throws
    
    /// Pause downloading an item.
    /// - Throws: DTGError.itemNotFound
    func pauseItem(id: String) throws
    
    /// Remove an existing item from storage, deleting all related files.
    /// - Throws: DTGError.itemNotFound
    func removeItem(id: String) throws
    
    /// Get a playable URL for an item.
    /// - Returns: a playback URL, or nil.
    /// - Throws: DTGError.itemNotFound
    func itemPlaybackUrl(id: String) throws -> URL?
    
    
    /// Handles events of a background session waiting to be processed.
    ///
    /// - Parameters:
    ///   - identifier: The background url session identifier.
    ///   - completionHandler: the completionHandler to call when finished handling the events.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void)
    
    /// handles all the setup needed by the content manager, must be called on AppDelegate in:
    ///
    /// ```func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool```
    func setup() throws
    
    /// Set the default audio bitrate for size-estimation purposes. Defaults to 64000.
    func setDefaultAudioBitrateEstimation(bitrate: Int)
}

public class DTGSelectionOptions {
    
    /// Initialize a new SelectionSettings object.
    /// The default behavior is as follows:
    /// - Video: select the track most suitable for the current device (codec, width, height)
    /// - Audio: select the default, as specified by the HLS playlist
    /// - Subtitles: select nothing
    public init() {}

    /// Audio languages to download.
    ///
    /// The languages are specified in ISO-639-1 (2 letters) or ISO-639-2 (3 letters) codes.
    ///
    /// Example: selecting French and German audio:
    /// ```
    /// ["fr", "de"]
    /// ```
    public var audioLanguages: [String]? = nil {
        didSet {
            if audioLanguages != nil {
                allAudioLanguages = false
            }
        }
    }
    
    /// Text languages to download.
    ///
    /// The languages are specified in ISO-639-1 (2 letters) or ISO-639-2 (3 letters) codes.
    ///
    /// Example: selecting English subtitles:
    /// ```
    /// ["en"]
    /// ```
    public var textLanguages: [String]? = nil {
        didSet {
            if textLanguages != nil {
                allTextLanguages = false
            }
        }
    }
    
    /// Select all audio languages.
    public var allAudioLanguages: Bool = false {
        didSet {
            if allAudioLanguages {
                audioLanguages = nil
            }
        }
    }
    
    /// Select all subtitle languages.
    public var allTextLanguages: Bool = false {
        didSet {
            if allTextLanguages {
                textLanguages = nil
            }
        }
    }
    
    /// Preferred video codecs.
    ///
    /// The default is to allow all codecs in quality order: `[.hevc, .avc1]`.
    ///
    /// - Note:
    /// A given codec may be selected even if it isn't listed if there's no other way to satisfy the download.
    /// For example, if the list is `[.hevc]`, but the stream has only `avc1`, `avc1` will be selected. Likewise,
    /// if the list contains only `.hevc` but the device does not support it, `.avc1` will be selected.
    public var videoCodecs: [VideoCodec]? = nil 
    
    /// Preferred audio codecs.
    ///
    /// The default is to allow all codecs in quality order: [.eac3, .ac3, .mp4a].
    ///
    /// - Note:
    /// A given codec may be selected even if it isn't listed if there's no other way to satisfy the download.
    /// For example, if the list is `[.ac3, .eac3]`, but the stream has only `mp4a`, `mp4a` will be selected. Likewise,
    /// if the list contains only `.eac3` but the device does not support it, `.ac3` or `.mp4a` will be selected.
    public var audioCodecs: [AudioCodec]? = nil
    
    /// Preferred video width in pixels. DTG will prefer the smallest rendition that is large enough.
    public var videoWidth: Int? = nil
    
    /// Preferred video height in pixels. DTG will prefer the smallest rendition that is large enough.
    public var videoHeight: Int? = nil
    
    
    /// Preferred video bitrates, **per codec**.
    ///
    /// By default, the best bitrate for the device is selected. If specified, this list
    /// overrides `videoCodecs`.
    ///
    /// Example: `[.hevc(2700000), .avc1(3200000)]`
    ///
    /// - Attention:
    /// When setting this property, it is advised to include the max bitrate for every codec.
    /// Otherwise, if a codec not on this list is selected for download, the selected
    /// bitrate is not defined.
    public var videoBitrates: [VideoBitrate]? = nil {
        didSet {
            videoCodecs = nil
        }
    }
    
    /// Allow or disallow codecs that are not implemented in hardware.
    /// iOS 11 and up support HEVC, but hardware support is only available in iPhone 7 and later.
    /// Using a software decoder causes higher energy consumption, affecting battery life.
    public var allowInefficientCodecs: Bool = false
    
    public enum VideoBitrate {
        case avc1(_ preferredBitrate: Int)
        case hevc(_ preferredBitrate: Int)
    }
    
    public enum VideoCodec {
        
        /// AVC1 codec, AKA H.264
        case avc1
        
        /// HEVC codec, AKA HVC1 or H.265
        case hevc
    }
    
    public enum AudioCodec {
        /// MP4A
        case mp4a
        
        /// AC3: Dolby Atmos
        case ac3
        
        /// E-AC3: Dolby Digital Plus (Enhanced AC3)
        case eac3
    }
    
    // Convenience methods for setting the properties.
    
    public func setPreferredVideoWidth(_ width: Int) -> Self {
        self.videoWidth = width
        return self
    }
    
    public func setPreferredVideoHeight(_ height: Int) -> Self {
        self.videoHeight = height
        return self
    }
    
    public func setPreferredVideoBitrates(_ prefs: [VideoBitrate]) -> Self {
        self.videoBitrates = prefs
        return self
    }
    
    public func setPreferredVideoCodecs(_ codecs: [VideoCodec]) -> Self {
        self.videoCodecs = codecs
        return self
    }
    
    public func setPreferredAudioCodecs(_ codecs: [AudioCodec]) -> Self {
        self.audioCodecs = codecs
        return self
    }
    
    public func setAudioLanguages(_ langs: [String]) -> Self {
        self.audioLanguages = langs
        return self
    }
    
    public func setTextLanguages(_ langs: [String]) -> Self {
        self.textLanguages = langs
        return self
    }
    
    public func setAllAudioLanguages(_ all: Bool = true) -> Self {
        self.allAudioLanguages = true
        return self
    }
    
    public func setAllTextLanguages(_ all: Bool = true) -> Self {
        self.allTextLanguages = true
        return self
    }
}

extension DTGContentManager {
    public func setLogLevel(_ logLevel: LogLevel) {
        log.outputLevel = logLevel.asXCGLoggerLevel()
    }
}

/// Delegate that will receive download events.
public protocol ContentManagerDelegate: class {
    /// Some data was downloaded for the item. 
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?)
    
    /// Item has changed state. in case state will be failed, the error will be provided (interupted state could also provide error).
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?)
}

/// A downloadable item.
public protocol DTGItem {
    /// The item's unique id.
    var id: String { get }
    
    /// The items's remote URL.
    var remoteUrl: URL { get }
    
    /// The item's current state.
    var state: DTGItemState { get }
    
    /// Estimated size of the item.
    var estimatedSize: Int64? { get }
    
    /// Downloaded size in bytes.
    var downloadedSize: Int64 { get }
        
    /// The selected text tracks for download (when download finishes this represents the downloaded tracks)
    var selectedTextTracks: [TrackInfo] { get }
    
    /// The selected audio tracks for download (when download finishes this represents the downloaded tracks)
    var selectedAudioTracks: [TrackInfo] { get }
}

/// Information about a Video track.
public protocol DTGVideoTrack {
    /// Width in pixels.
    var width: Int? { get }
    
    /// Height in pixels.
    var height: Int? { get }
    
    /// Bitrate.
    var bitrate: Int { get }
}

/// `DTGItemStartableState` represents startable states
public enum DTGItemStartableState {
    case inProgress, paused, interrupted
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
    
    /// Item has finished downloading and processing.
    case completed
    
    /// Item download has failed (fatal error cannot use this item again).
    case failed
    
    /// Item download was interrupted (can be caused by error that we can recover from)
    /// 
    /// For example: when we can call start item again after this state.
    case interrupted
    
    /// Item is removed. This is only a temporary state, as the item is actually removed.
    case removed
    
    /// Item had a failure related to db access.
    /// If this state is sent make sure to save the id of the item to later try again.
    ///
    /// - Attention:
    /// It is important to keep this state seperatly because usually this will happen in a rare case
    /// where the device is out of storage and actions can't be made,
    /// meaning we cannot update item progress and its real state will be the last state that is was,
    /// for example for an item in the middle of a download that last state will be "in progress".
    /// if the storage will be available again we recommand removing the item and starting it again.
    case dbFailure
    
    init?(value: String) {
        switch value {
        case DTGItemState.new.asString(): self = .new
        case DTGItemState.metadataLoaded.asString(): self = .metadataLoaded
        case DTGItemState.inProgress.asString(): self = .inProgress
        case DTGItemState.paused.asString(): self = .paused
        case DTGItemState.completed.asString(): self = .completed
        case DTGItemState.failed.asString(): self = .failed
        case DTGItemState.interrupted.asString(): self = .interrupted
        case DTGItemState.removed.asString(): self = .removed
        case DTGItemState.dbFailure.asString(): self = .dbFailure
        default: return nil
        }
    }
    
    public func asString() -> String {
        switch self {
        case .new: return "new"
        case .metadataLoaded: return "metadataLoaded"
        case .inProgress: return "inProgress"
        case .paused: return "paused"
        case .completed: return "completed"
        case .failed: return "failed"
        case .interrupted: return "interrupted"
        case .removed: return "removed"
        case .dbFailure: return "dbFailure"
        }
    }
}

public enum LogLevel {
    case verbose
    case debug
    case info
    case warning
    case error
    
    func asXCGLoggerLevel() -> XCGLogger.Level {
        switch self {
        case .verbose: return .verbose
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}
