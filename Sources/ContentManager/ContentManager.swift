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
import XCGLogger

let log = XCGLogger.default

/************************************************************/
// MARK: - DTGTrackType
/************************************************************/

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

/************************************************************/
// MARK: - DTGError
/************************************************************/

public enum DTGError: Error {
    case itemNotFound(itemId: String)
    /// sent when item cannot be started (casued when item state is other than metadata loaded)
    case invalidState(itemId: String)
}

/************************************************************/
// MARK: - DownloadItem
/************************************************************/

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

/************************************************************/
// MARK: - DTGFilePaths
/************************************************************/

class DTGFilePaths {
    
    private static let mainDirName = "KalturaDTG"
    private static let itemsDirName = "items"
    
    private static let defaultStoragePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent(mainDirName, isDirectory: true)
    }()
    
    static var storagePath = DTGFilePaths.defaultStoragePath
    
    class var itemsDirUrl: URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true)
    }
    
    static func itemDirUrl(forItemId id: String) -> URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true).appendingPathComponent(id.safeItemPathName(), isDirectory: true)
    }
}

/************************************************************/
// MARK: - ContentManager
/************************************************************/

public class ContentManager: NSObject, ContentManagerProtocol {
    /// shared singleton object
    public static let shared: ContentManagerProtocol = ContentManager()
    private override init() {
        self.db = RealmDB(dispatchQueue: dispatch)
        super.init()
        #if DEBUG
            let logLevel: XCGLogger.Level = .debug
        #else
            let logLevel: XCGLogger.Level = .info
        #endif
        log.setup(level: logLevel, showLevel: true, showFileNames: true, showLineNumbers: true, showDate: true)
        log.debug("*** ContentManager ***")
    }
    
    public weak var delegate: DTGItemDelegate?

    public var storagePath: URL {
        get {
            return DTGFilePaths.storagePath
        }
        set {
            DTGFilePaths.storagePath = newValue
        }
    }
    
    var started = false
    var server = GCDWebServer()!
    var serverUrl: URL? {
        return server.isRunning ? server.serverURL : nil
    }
    
    /// Dispatch queue to handle all actions on a background queue to make sure not block main.
    fileprivate let dispatch = DispatchQueue(label: "com.kaltura.dtg.content-manager")
    
    // db interface instance
    let db: DB
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
    public func start() throws {
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
    
    public func stop() {
        // stop server
        server.stop()
        started = false
    }

    public func resumeInterruptedItems() throws {
        for item in itemsByState(.inProgress) {
            try startItem(id: item.id)
        }
    }

    public func itemsByState(_ state: DTGItemState) -> [DTGItem] {
        
        return db.items(byState: state)
    }
    
    public func itemById(_ id: String) -> DTGItem? {
        
        return db.item(byId: id)
    }
    
    public func addItem(id: String, url: URL) -> DTGItem? {
        
        if db.item(byId: id) != nil {
            return nil
        }
        
        let item = DownloadItem(id: id, url: url)
        self.update(item: item)

        return item
    }

    public func loadItemMetadata(id: String, preferredVideoBitrate: Int?) throws {
        
        var item = try findItemOrThrow(id)
        
        let localizer = HLSLocalizer(id: id, url: item.remoteUrl, preferredVideoBitrate: preferredVideoBitrate)
        
        DispatchQueue.global().async {
            do {
                try localizer.loadMetadata()
                try localizer.saveLocalFiles()
                // when localizer finished add the tasks and update the item
                self.db.set(tasks: localizer.tasks)
                item.state = .metadataLoaded
                item.estimatedSize = localizer.estimatedSize
                self.update(item: item)
            } catch {
                self.update(itemState: .failed, byId: id, error: error)
            }
        }
    }
    
    public func startItem(id: String) throws {
        // find in db
        let item = try findItemOrThrow(id)
        
        // for item to start downloading state must be metadataLoaded/paused or inProgress + no active downloader for the selected id.
        guard item.state == .metadataLoaded || item.state == .paused || item.state == .interrupted || (item.state == .inProgress && self.downloaders[id] == nil) else {
            throw DTGError.invalidState(itemId: id)
        }
        
        // make sure we have tasks to perform
        let tasks = db.tasks(forItemId: id)
        guard tasks.count > 0 else {
            log.warning("no tasks for this id")
            return
        }
        
        let downloader = DefaultDownloader(itemId: id, tasks: tasks)
        downloader.delegate = self
        self.downloaders[id] = downloader
        try downloader.start()
        
        self.update(itemState: .inProgress, byId: id)
    }

    public func pauseItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            log.warning("no downloader for this id")
            return
        }
        // pause the downloads and remove the downloader
        downloader.pause()
    }

    public func removeItem(id: String) throws {
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
        self.delegate?.item(id: id, didChangeToState: .removed, error: nil)
    }

    public func itemPlaybackUrl(id: String) throws -> URL? {
        return serverUrl?.appendingPathComponent("\(id.safeItemPathName())/master.m3u8")
    }
    
    public func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
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

extension ContentManager: DownloaderDelegate {
    
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64) {
        guard var item = self.db.item(byId: downloader.dtgItemId) else {
            log.warning("no item for request id")
            return
        }
        item.downloadedSize += bytesWritten
        self.update(item: item)
        self.delegate?.item(id: downloader.dtgItemId, didDownloadData: item.downloadedSize, totalBytesEstimated: item.estimatedSize)
    }
    
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask]) {
        log.debug("downloading paused")
        // save pasued tasks to db
        self.db.update(tasks)
        // update state
        self.update(itemState: .paused, byId: downloader.dtgItemId)
        self.downloaders[downloader.dtgItemId] = nil
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
        log.debug("downloader state: \(newState.rawValue)")
        if newState == .idle {
            self.update(itemState: .completed, byId: downloader.dtgItemId)
            // remove the downloader, no longer needed
            self.downloaders[downloader.dtgItemId] = nil
        }
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        switch error {
        case DownloaderError.http(let statusCode, let rootError):
            if statusCode >= 500 {
                self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: rootError)
            } else {
                self.update(itemState: .failed, byId: downloader.dtgItemId, error: error)
            }
        default: self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: error)
        }
        
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

extension ContentManager {
    
    fileprivate func update(item: DownloadItem) {
        let oldItem = self.db.item(byId: item.id)
        db.update(item: item)
        if oldItem?.state != item.state {
            self.dispatch.sync {
                self.delegate?.item(id: item.id, didChangeToState: item.state, error: nil)
            }
        }
    }
    
    fileprivate func update(itemState: DTGItemState, byId id: String, error: Error? = nil) {
        self.db.update(itemState: itemState, byId: id)
        self.dispatch.sync {
            self.delegate?.item(id: id, didChangeToState: itemState, error: error)
        }
    }
    
    @discardableResult
    fileprivate func findItemOrThrow(_ id: String) throws -> DownloadItem {
        if let item = db.item(byId: id) {
            return item
        } else {
            throw DTGError.itemNotFound(itemId: id)
        }
    }
}
