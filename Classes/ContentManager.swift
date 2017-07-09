
import Foundation
import M3U8Kit

//func TODO() {
//    fatalError("Not implemented")
//}

var TODO: Void {
    fatalError("Not implemented")
}

public let DTGSharedContentManager: ContentManager = ContentManagerImp()

class ContentManagerImp: NSObject, ContentManager {
    static var downloadPath: URL {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent("DTG/items", isDirectory: true)
    }
    
    var maxConcurrentDownloads: Int = 1
    
    var started = false
    fileprivate var errorObservers = [DTGErrorCallback]()
    fileprivate var progressObservers = [DTGProgressCallback]()
    fileprivate var stateObservers = [DTGStateCallback]()
    fileprivate var serverUrl: URL?
        
    /// Start the content manager. This also starts the playback server.
    func start() {
        
        TODO
        // prepare db
        // start server
        started = true
    }
    
    /// Stop the content manager, including the playback server.
    func stop() {
        TODO
        // stop server
        started = false
    }

    /// Resume downloading of items that were in progress when stop() was called.
    func resumeInterruptedItems() {
        for item in itemsByState(.inProgress) {
            startItem(id: item.id)
        }
    }

    func itemsByState(_ state: DTGItemState) -> [DTGItem] {
        TODO
        // get from db
        return []
    }
    
    func itemById(_ id: String) -> DTGItem? {
        TODO
        // get from db
        return nil
    }
    
    func addItem(id: String, url: String) -> DTGItem? {
        TODO
        if itemById(id) != nil {
            return nil
        }
        
        // add to db
        
        // return the new object
        return nil
    }

    /// Load metadata for the given item id.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - callback: block that takes the updated item.
    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: DTGMetadataCallback) {
        TODO
        // find item in db
        // load master playlist
        // load relevant media playlists
        // store data to db
    }

    /// Start or resume item download.
    func startItem(id: String) {
        TODO
        // find in db
        // tell download manager to start/resume
    }

    /// Pause downloading an item.
    func pauseItem(id: String) {
        TODO
        // find in db
        // if in progress, tell download manager to pause
    }

    /// Remove an existing item from storage, deleting all related files.
    func removeItem(id: String) {
        TODO
        // find in db
        guard let item = itemById(id) else {return}
        // if in progress, cancel
        // remove all files
        // remove from db
        // notify observers
        stateObservers.forEach { (callback) in
            callback(item, .removed)
        }
    }

    /// Get a playable URL for an item.
    /// - Returns: a playback URL, or nil.
    func itemPlaybackUrl(id: String) -> URL? {
        return serverUrl?.appendingPathComponent("\(id)/master.m3u8")
    }
}


extension ContentManagerImp {
    
    /// Add error observer.
    func addErrorObserver(owner: Any, callback: @escaping DTGErrorCallback) {
        errorObservers.append(callback)
    }
    
    /// Remove error observer.
    func removeErrorObserver(owner: Any) {
        TODO
    }
    
    /// Add progress observer.
    func addProgressObserver(owner: Any, callback: @escaping DTGProgressCallback) {
        progressObservers.append(callback)
    }
    
    /// Remove progress observer.
    func removeProgressObserver(owner: Any) {
        TODO
    }
    
    /// Add state change observer.
    func addStateObserver(owner: Any, callback: @escaping DTGStateCallback) {
        stateObservers.append(callback)
    }
    
    /// Remove state change observer.
    func removeStateObserver(owner: Any) {
        TODO
    }
}
