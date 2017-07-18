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
import GCDWebServer

public let DTGSharedContentManager: ContentManager = ContentManagerImp()

enum DTGTrackType {
    case video
    case audio
    case text
    
    static var allTypes: [DTGTrackType] {
        return [.video, .audio, .text]
    }
    
    init?(type: String) {
        switch type {
        case "video": self = .video
        case "audio": self = .audio
        case "text": self = .text
        default: return nil
        }
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
    /// sent when item cannot be started (could be casued when item state is other than metadata loaded)
    case itemCantStart(itemId: String)
}

struct DownloadItem: DTGItem {
    
    var id: String

    var remoteUrl: URL

    var state: DTGItemState = .new

    var estimatedSize: Int64?

    var downloadedSize: Int64 = 0
    
    init(id: String, url: URL) {
        self.id = id
        self.remoteUrl = url
    }
}

class DTGFilePaths {
    
    static let mainDirName = "KalturaDTG"
    static let itemsDirName = "items"
    
    static let defaultStoragePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return URL(string: libraryDir.appendingPathComponent(mainDirName, isDirectory: true).absoluteString, relativeTo: libraryDir)!
    }()
    
    class var itemsDirUrl: URL {
        return self.defaultStoragePath.appendingPathComponent(itemsDirName)
    }
    
    static func itemDirUrl(forItemId id: String) -> URL {
        return self.defaultStoragePath.appendingPathComponent(itemsDirName, isDirectory: true).appendingPathComponent(id.safeItemPathName(), isDirectory: true)
    }
}

class ContentManagerImp: NSObject, ContentManager {
    weak var itemDelegate: DTGItemDelegate?

    lazy var storagePath = DTGFilePaths.defaultStoragePath
    
    var maxConcurrentDownloads: Int = 1
    
    var started = false
    var server = GCDWebServer()!
    var serverUrl: URL? {
        return server.isRunning ? server.serverURL : nil
    }
      
    // db interface instance
    let db = DB.shared
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
    
    override init() {
        print("*** ContentManager ***")
    }
    
    func start() throws {
        if started {
            return
        }
        
        // start server
        server.addGETHandler(forBasePath: "/", directoryPath: DTGFilePaths.itemsDirUrl.path, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
        try server.start(options: [GCDWebServerOption_BindToLocalhost: true,
                               GCDWebServerOption_Port: 0,
                               GCDWebServerOption_AutomaticallySuspendInBackground: false,
                               ])
        
        started = true
    }
    
    func stop() {
        // stop server
        server.stop()
        started = false
    }

    func resumeInterruptedItems() throws {
        for item in itemsByState(.inProgress) {
            try startItem(id: item.id)
        }
    }

    func itemsByState(_ state: DTGItemState) -> [DTGItem] {
        
        return db.items(byState: state)
    }
    
    func itemById(_ id: String) -> DTGItem? {
        
        return db.item(byId: id)
    }
    
    func addItem(id: String, url: URL) -> DTGItem? {
        
        if db.item(byId: id) != nil {
            return nil
        }
        
        let item = DownloadItem(id: id, url: url)
        db.update(item: item)

        return item
    }

    func loadItemMetadata(id: String, preferredVideoBitrate: Int?, callback: @escaping (DTGItem?, DTGVideoTrack?, Error?) -> Void) {
        
        guard var item = self.db.item(byId: id) else { return }
        
        let localizer = HLSLocalizer(id: id, url: item.remoteUrl, preferredVideoBitrate: preferredVideoBitrate)
        
        DispatchQueue.global(qos: .default).async {
            do {
                try localizer.loadMetadata()
                self.db.set(tasks: localizer.tasks)
                item.state = .metadataLoaded
                item.estimatedSize = localizer.estimatedSize
                self.db.update(item: item)
                try localizer.saveLocalFiles()
                callback(item, localizer.videoTrack, nil)
            } catch {
                callback(nil, nil, error)
            }
        }
    }
    
    @discardableResult
    func findItemOrThrow(_ id: String) throws -> DownloadItem {
        if let item = db.item(byId: id) {
            return item
        } else {
            throw DTGError.itemNotFound(itemId: id)
        }
    }
    
    func startItem(id: String) throws {
        // find in db
        let item = try findItemOrThrow(id)
        
        // for item to start downloading state must be metadataLoaded/paused or inProgress + no active downloader for the selected id.
        guard item.state == .metadataLoaded || item.state == .paused || (item.state == .inProgress && self.downloaders[id] == nil) else { // FIXME: make sure with Noam this are the only 2 possibilties.
            throw DTGError.itemCantStart(itemId: id)
        }
        
        // make sure we have tasks to perform
        let tasks = db.tasks(forItemId: id)
        guard tasks.count > 0 else {
            print("error: no tasks for this id")
            return
        }
        
        let downloader = DefaultDownloader(itemId: id, tasks: tasks)
        downloader.delegate = self
        self.downloaders[id] = downloader
        try downloader.start()
        
        db.update(itemState: .inProgress, byId: id)
    }

    func pauseItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            print("error: no downloader for this id")
            return
        }
        // pause the downloads and remove the downloader
        downloader.pause()
        self.downloaders[id] = nil
    }

    func removeItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, cancel
        if let downloader = self.downloaders[id] {
            downloader.cancel()
            self.downloaders[id] = nil
        }
        
        // remove all files
        let itemPath = DTGFilePaths.itemDirUrl(forItemId: id)
        try FileManager.default.removeItem(at: itemPath)
        
        // remove from db
        db.removeItem(byId: id)
        
        // notify delegate
        db.update(itemState: .removed, byId: id)
    }

    func itemPlaybackUrl(id: String) throws -> URL? {
        return serverUrl?.appendingPathComponent("\(id.safeItemPathName())/master.m3u8")
    }
    
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        for (_, downloader) in self.downloaders {
            if downloader.sessionIdentifier == identifier {
                downloader.backgroundSessionCompletionHandler = completionHandler
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
        guard var item = self.db.item(byId: downloader.dtgItemId) else {
            print("error: no item for request id")
            return
        }
        item.downloadedSize += bytesWritten
        self.db.update(item: item)
        self.itemDelegate?.item(id: downloader.dtgItemId, didDownloadData: item.downloadedSize, totalBytesEstimated: item.estimatedSize)
    }
    
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask]) {
        print("downloading paused")
        // save pasued tasks to db
        self.db.update(tasks)
        // update state
        self.db.update(itemState: .paused, byId: downloader.dtgItemId)
    }
    
    func downloaderDidCancelDownloadTasks(_ downloader: Downloader) {
        // removes all tasks from the db
        self.db.removeTasks(withItemId: downloader.dtgItemId)
        // clear the downloader instance
        self.downloaders[downloader.dtgItemId] = nil
    }
    
    func downloader(_ downloader: Downloader, didFinishDownloading downloadItemTask: DownloadItemTask) {
        // remove the task from the db tasks objects
        self.db.remove([downloadItemTask])
    }
    
    func downloader(_ downloader: Downloader, didChangeToState newState: DownloaderState) {
        print("downloader state: \(newState.rawValue)")
        if newState == .idle {
            // TODO:
            // make sure all handlng has been done, 
            // DB and whatever before letting to app know the download was finished and now playable
            self.db.update(itemState: .completed, byId: downloader.dtgItemId)
            // remove the downloader, no longer needed
            self.downloaders[downloader.dtgItemId] = nil
        }
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        self.itemDelegate?.item(id: downloader.dtgItemId, didFailWithError: error)
    }
}

/************************************************************/
// MARK: - App Lifecycle Observing
/************************************************************/

extension ContentManagerImp {
    
    func addAppLifecycleObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(onTermination), name: .UIApplicationWillTerminate, object: nil)
    }
    
    @objc private func onTermination() {
        // when terminating the app while downloads are still running,
        // we need to pause all active downloads to make sure we can resume from the point we stopped later on.
        self.pauseAllItems()
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

extension ContentManagerImp {
    /// Pauses all downloading items
    fileprivate func pauseAllItems() {
        for (id, _) in downloaders {
            try? self.pauseItem(id: id)
        }
    }
}
