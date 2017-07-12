
import Foundation

var TODO: Void {
    //fatalError("Not implemented")
    print("")
}

public let DTGSharedContentManager: ContentManager = ContentManagerImp()

enum DTGTrackType {
    case video
    case audio
    case text
    
    static var allTypes: [DTGTrackType] {
        return [.video, .audio, .text]
    }
    
    func asString() -> String {
        switch self {
        case .video: return "video"
        case .audio: return "audio"
        case .text: return "text"
        }
    }
}

struct MockItem: DTGItem {
    
    weak var contentManager: ContentManager?
    
    var id: String

    var remoteUrl: URL

    var state: DTGItemState = .new {
        didSet {
            contentManager?.itemDelegate?.item(id: self.id , didChangeToState: state)
        }
    }

    var estimatedSize: Int64?

    var downloadedSize: Int64?
    
    init(id: String, url: URL, contentManager: ContentManager) {
        self.id = id
        self.remoteUrl = url
        self.contentManager = contentManager
    }
}

class MockDb {
    private var itemMap = [String: MockItem]()
    private var stateMap = [DTGItemState: [MockItem]]()
    private var taskMap = [String: [DownloadItemTask]]()
    private var itemState = [String: DTGItemState]()
    
    func itemById(_ id: String) -> MockItem? {
        return itemMap[id]
    }
    
    func updateItem(_ item: MockItem) {
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
    
    func setTasks(_ itemId: String, tasks: [DownloadItemTask]) {
        taskMap[itemId] = tasks
    }
}

class ContentManagerImp: NSObject, ContentManager {
    
    weak var itemDelegate: DTGItemDelegate?

    lazy var storagePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return URL(string: libraryDir.appendingPathComponent("KalturaDTG", isDirectory: true).absoluteString, relativeTo: libraryDir)!
    }()
    
    var maxConcurrentDownloads: Int = 1
    
    var started = false
    fileprivate var serverUrl: URL?
      
    // TEMP db
    var mockDb = MockDb()
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
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
    func resumeInterruptedItems() throws {
        for item in itemsByState(.inProgress) {
            try startItem(id: item.id)
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
        
        var mockItem = MockItem(id: id, url: url, contentManager: self)
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
        
        DispatchQueue.global(qos: .default).async {
            do {
                try localizer.loadMetadata()
                item.state = .metadataLoaded
                self.mockDb.updateItem(item)
                print(localizer.duration)
                print(localizer.tasks)
                self.mockDb.setTasks(id, tasks: localizer.tasks) // FIXME: remove later if not needed
                item.estimatedSize = localizer.estimatedSize
                try localizer.localize()
                callback(item, localizer.videoTrack, nil)
            } catch {
                callback(nil, nil, error)
            }
        }
        
        
        return;
        
        
        TODO
        // find item in db
        // load master playlist
        // load relevant media playlists
        // store data to db
    }

    func startItem(id: String) throws {
        TODO
        // find in db
        // tell download manager to start/resume
        
        // FIXME: mock implementation
        guard let tasks = mockDb.tasksForItem(id) else {
            print("error: no tasks for this id")
            return
        }
        let downloader = DefaultDownloader(itemId: id, tasks: tasks)
        downloader.delegate = self
        self.downloaders[id] = downloader
        try downloader.start()
        self.itemDelegate?.item(id: id, didChangeToState: .inProgress)
    }

    func pauseItem(id: String) {
        TODO
        // find in db
        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            print("error: no downloader for this id")
            return
        }
        downloader.pause()
    }

    func removeItem(id: String) {
        TODO
        // find in db
        guard let item = itemById(id) else { return }

        // if in progress, cancel
        // remove all files
        // remove from db
        // notify observers
        itemDelegate?.item(id: id, didChangeToState: .removed)
    }

    func itemPlaybackUrl(id: String) -> URL? {
        return serverUrl?.appendingPathComponent("\(id)/master.m3u8")
    }
}

/************************************************************/
// MARK: - DownloaderDelegate
/************************************************************/

extension ContentManagerImp: DownloaderDelegate {
    
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64) {
        print("item: \(downloader.dtgItemId), didProgress, bytes written: \(bytesWritten)")
        let totalBytesEstimated = self.mockDb.itemById(downloader.dtgItemId)?.estimatedSize ?? 0
        self.itemDelegate?.item(id: downloader.dtgItemId, didDownloadData: bytesWritten, totalBytesEstimated: totalBytesEstimated)
    }
    
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask]) {
        print("downloading paused")
        TODO
        // save pasued tasks to db
        self.itemDelegate?.item(id: downloader.dtgItemId, didChangeToState: .paused)
    }
    
    func downloaderDidCancelDownloadTasks(_ downloader: Downloader) {
        TODO
        // remove all data from db
        // change item state to removed
    }
    
    func downloader(_ downloader: Downloader, didFinishDownloading downloadItemTask: DownloadItemTask) {
        print("finished downloading: \(String(describing: downloadItemTask))")
    }
    
    func downloader(_ downloader: Downloader, didChangeToState newState: DownloaderState) {
        print("downloader state: \(newState.rawValue)")
        if newState == .idle {
            TODO
            // make sure all handlng has been done, 
            // DB and whatever before letting to app know the download was finished and now playable
            if var item = self.mockDb.itemById(downloader.dtgItemId) {
                item.state = .completed
                mockDb.updateItem(item)
            }
        }
    }
    
    func downloader(_ downloader: Downloader, didBecomeInvalidWithError error: Error?) {
        
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        self.itemDelegate?.item(id: downloader.dtgItemId, didFailWithError: error)
    }
}
