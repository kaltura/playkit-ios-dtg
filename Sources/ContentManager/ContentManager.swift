
import Foundation

var TODO: Void {
    fatalError("Not implemented")
}

public let DTGSharedContentManager: ContentManager = ContentManagerImp()

enum DTGTrackType {
    case video
    case audio
    case text
}

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

struct MockDb {
    private var itemMap = [String: MockItem]()
    private var stateMap = [DTGItemState: [MockItem]]()
    private var taskMap = [String: [DownloadItemTask]]()
    
    init() {
        
    }
    
    func itemById(_ id: String) -> MockItem? {
        return itemMap[id]
    }
    
    mutating func updateItem(_ item: MockItem) {
        itemMap[item.id] = item
        let state = item.state
        if var list = stateMap[state] {
            list.append(item)
        } else {
            stateMap[state] = [item]
        }
    }
    
    func itemsByState(_ state: DTGItemState) -> [MockItem] {
        return stateMap[state] ?? []
    }
    
    func tasksForItem(_ id: String) -> [DownloadItemTask]? {
        return taskMap[id]
    }
    
    mutating func setTasks(_ itemId: String, tasks: [DownloadItemTask]) {
        taskMap[itemId] = tasks
    }
}

class ContentManagerImp: NSObject, ContentManager {
    
    var itemDelegate: DTGItemDelegate?

    lazy var storagePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent("KalturaDTG", isDirectory: true)
    }()
    
    var maxConcurrentDownloads: Int = 1
    
    var started = false
    fileprivate var serverUrl: URL?
      
    // TEMP db
    var mockDb = MockDb()
        
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
        
        return mockDb.itemsByState(state)

        TODO
        // get from db
        return []
    }
    
    func itemById(_ id: String) -> DTGItem? {
        
        return mockDb.itemById(id)
        TODO
        // get from db
        return nil
    }
    
    func addItem(id: String, url: URL) -> DTGItem? {
        
        if mockDb.itemById(id) != nil {
            return nil
        }
        
        let mockItem = MockItem(id: id, url: url)
        mockDb.updateItem(mockItem)
        return mockItem
        
        
        TODO
        // add to db
        
        // return the new object
        return nil
    }

    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: @escaping (DTGItem?, DTGVideoTrack?, Error?) -> Void) {
        
        guard var item = mockDb.itemById(id) else { return }
        
        let localizer = HLSLocalizer(id: id, url: item.remoteUrl, preferredVideoBitrate: preferredVideoBitrate, storagePath: storagePath)
        
        localizer.loadMetadata { (error) in
            if error != nil {
                callback(nil, nil, error)
            } else {
                mockDb.updateItem(item)
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
