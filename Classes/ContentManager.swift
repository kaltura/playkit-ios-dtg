
import Foundation
import M3U8Kit

var TODO: Void {
    fatalError("Not implemented")
}

public let DTGSharedContentManager: ContentManager = ContentManagerImp()

struct MockItem: DTGItem {
    var id: String

    var remoteUrl: URL

    var state: DTGItemState = .new

    var estimatedSize: Int64?

    var downloadedSize: Int64?
    
    init(id: String, url: URL) {
        self.id = id
        self.remoteUrl = url
    }
}

class ContentManagerImp: NSObject, ContentManager {
    
    var itemDelegate: DTGItemDelegate?

    var storagePath: URL {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent("KalturaDTG", isDirectory: true)
    }
    
    var maxConcurrentDownloads: Int = 1
    
    var started = false
    fileprivate var serverUrl: URL?
    
    
    // TEMP db
    var mockDb = [String: MockItem]()
        
    override init() {
        print("*** ContentManager ***")
    }
    
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
        
        return mockDb[id]
        
        TODO
        // get from db
        return nil
    }
    
    func addItem(id: String, url: URL) -> DTGItem? {
        
        if mockDb[id] != nil {
            return nil
        }
        
        let mockItem = MockItem(id: id, url: url)
        mockDb[id] = mockItem
        return mockItem
        
        
        TODO
        // add to db
        
        // return the new object
        return nil
    }

    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: DTGMetadataCallback) {
        
        guard var item = mockDb[id] else { return }
        
        let localizer = DTGItemLocalizer(id: id, url: item.remoteUrl, preferredVideoBitrate: preferredVideoBitrate, storagePath: storagePath)
        
        localizer.loadMetadata { (error) in
            if error != nil {
                callback(nil, nil, nil)
            } else {
                print(localizer.duration)
                print(localizer.tasks)
                item.estimatedSize = localizer.estimatedSize
                callback(item, localizer.videoTrack, nil)
            }
        }
        
        return
        
        
        TODO
        // find item in db
        // load master playlist
        // load relevant media playlists
        // store data to db
    }

    func startItem(id: String) {
        TODO
        // find in db
        // tell download manager to start/resume
    }

    func pauseItem(id: String) {
        TODO
        // find in db
        // if in progress, tell download manager to pause
    }

    func removeItem(id: String) {
        TODO
        // find in db
        guard let item = itemById(id) else {return}
        // if in progress, cancel
        // remove all files
        // remove from db
        // notify observers
        itemDelegate?.item(id: id, didMoveToState: .removed)
    }

    func itemPlaybackUrl(id: String) -> URL? {
        return serverUrl?.appendingPathComponent("\(id)/master.m3u8")
    }
}
