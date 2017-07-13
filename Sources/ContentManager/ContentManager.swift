
import Foundation
import GCDWebServer

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

public enum DTGError: Error {
    case itemNotFound(itemId: String)
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
    private var taskMap = [String: [DownloadItemTask]]()
    
    func itemById(_ id: String) -> MockItem? {
        return itemMap[id]
    }
    
    func updateItem(_ item: MockItem) {
        itemMap[item.id] = item
    }
    
    func itemsByState(_ state: DTGItemState) -> [MockItem] {
        var items = [MockItem]()
        for (_, item) in itemMap {
            if item.state == state {
                items.append(item)
            }
        }
        return items
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
    var server = GCDWebServer()!
    var serverUrl: URL? {
        return server.isRunning ? server.serverURL : nil
    }
      
    // TEMP db
    var db = MockDb()
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
    
    override init() {
        print("*** ContentManager ***")
    }
    
    /// Start the content manager. This also starts the playback server.
    func start() throws {
        if started {
            return
        }
        
        // TODO: prepare db
        
        // start server
        server.addGETHandler(forBasePath: "/", directoryPath: storagePath.appendingPathComponent("items").path, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
        try server.start(options: [GCDWebServerOption_BindToLocalhost: true,
                               GCDWebServerOption_Port: 0,
                               ])
        
        started = true
    }
    
    /// Stop the content manager, including the playback server.
    func stop() {
        // stop server
        server.stop()
        started = false
    }

    /// Resume downloading of items that were in progress when stop() was called.
    func resumeInterruptedItems() throws {
        for item in itemsByState(.inProgress) {
            try startItem(id: item.id)
        }
    }

    func itemsByState(_ state: DTGItemState) -> [DTGItem] {
        
        return db.itemsByState(state)

        
        // TODO: get from db
    }
    
    func itemById(_ id: String) -> DTGItem? {
        
        return db.itemById(id)
        
        // TODO: get from db
    }
    
    func addItem(id: String, url: URL) -> DTGItem? {
        
        if db.itemById(id) != nil {
            return nil
        }
        
        let item = MockItem(id: id, url: url, contentManager: self)
        db.updateItem(item)

        // TODO: add to db
        return item
    }

    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: @escaping (DTGItem?, DTGVideoTrack?, Error?) -> Void) {
        
        guard var item = db.itemById(id) else { return }
        
        let localizer = HLSLocalizer(id: id, url: item.remoteUrl, preferredVideoBitrate: preferredVideoBitrate, storagePath: storagePath)
        
        DispatchQueue.global(qos: .default).async {
            do {
                try localizer.loadMetadata()
                item.state = .metadataLoaded
                self.db.updateItem(item)
                self.db.setTasks(id, tasks: localizer.tasks) // FIXME: remove later if not needed
                item.estimatedSize = localizer.estimatedSize
                self.db.updateItem(item)
                try localizer.saveLocalFiles()
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
    
    func findItemOrThrow(_ id: String) throws -> MockItem {
        if let item = db.itemById(id) {
            return item
        } else {
            throw DTGError.itemNotFound(itemId: id)
        }
    }
    
    func startItem(id: String) throws {
        // find in db
        try findItemOrThrow(id)
        
        // tell download manager to start/resume
        
        // FIXME: mock implementation
        guard let tasks = db.tasksForItem(id) else {
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
        try findItemOrThrow(id)

        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            print("error: no downloader for this id")
            return
        }
        downloader.pause()
    }

    func removeItem(id: String) {
        try findItemOrThrow(id)

        // if in progress, cancel
        // remove all files
        // remove from db
        // notify observers
        itemDelegate?.item(id: id, didChangeToState: .removed)
    }

    func itemPlaybackUrl(id: String) -> URL? {
        return serverUrl?.appendingPathComponent("\(id)/master.m3u8")
    }
    
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        for (_, downloader) in self.downloaders {
            if downloader.sessionIdentifier == identifier {
                downloader.backgroundSessionCompetionHandler = completionHandler
                break
            }
        }
    }
}

/************************************************************/
// MARK: - DownloaderDelegate
/************************************************************/

extension ContentManagerImp: DownloaderDelegate {
    
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64) {
        print("item: \(downloader.dtgItemId), didProgress, bytes written: \(bytesWritten)")
        let totalBytesEstimated = self.db.itemById(downloader.dtgItemId)?.estimatedSize ?? 0
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
            if var item = self.db.itemById(downloader.dtgItemId) {
                item.state = .completed
                db.updateItem(item)
            }
        }
    }
    
    func downloader(_ downloader: Downloader, didBecomeInvalidWithError error: Error?) {
        
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        self.itemDelegate?.item(id: downloader.dtgItemId, didFailWithError: error)
    }
}
