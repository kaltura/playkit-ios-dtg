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
import PlayKitUtils
import RealmSwift

let log = XCGLogger.default

/************************************************************/
// MARK: - DownloadItemTaskType
/************************************************************/

enum DownloadItemTaskType {
    case video
    case audio
    case text
    case key
    
    static var allTypes: [DownloadItemTaskType] {
        return [.video, .audio, .text, .key]
    }
    
    init?(type: String) {
        switch type {
        case "video": self = .video
        case "audio": self = .audio
        case "text": self = .text
        case "key": self = .key
        default: return nil
        }
    }
    
    func asString() -> String {
        switch self {
        case .video: return "video"
        case .audio: return "audio"
        case .text: return "text"
        case .key: return "key"
        }
    }
}

/************************************************************/
// MARK: - DTGError
/************************************************************/

public enum DTGError: LocalizedError {
    case itemNotFound(itemId: String)
    /// sent when item cannot be started (casued when item state is other than metadata loaded)
    case invalidState(itemId: String)
    /// insufficient disk space to start or continue the download
    case insufficientDiskSpace(freeSpaceInMegabytes: Int)
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemId):
            return "The item (id: \(itemId)) of the action was not found"
        case .invalidState(let itemId):
            return "try to make an action with an invalid state (item id: \(itemId))"
        case .insufficientDiskSpace(let freeSpaceInMegabytes):
            return "insufficient disk space to start or continue the download, only have \(freeSpaceInMegabytes)MB free..."
        }
    }
}

/* ***********************************************************/
// MARK: - DownloadItem
/* ***********************************************************/

struct DownloadItem: DTGItem {
    
    let id: String 
    let remoteUrl: URL
    var state: DTGItemState = .new 
    var estimatedSize: Int64? 
    var downloadedSize: Int64 = 0 
    var availableTextTracks: [TrackInfo] = [] 
    var availableAudioTracks: [TrackInfo] = [] 
    var selectedTextTracks: [TrackInfo] = [] 
    var selectedAudioTracks: [TrackInfo] = [] 
    
    init(id: String, url: URL) {
        self.id = id
        self.remoteUrl = url
    }
}

public struct TrackInfo: Hashable {
    public let type: TrackType
    public let languageCode: String
    public let title: String
    
    var id: String {
        return "\(self.languageCode):\(self.title)"
    }
    
    public enum TrackType: String {
        case audio
        case text
    }
}

/* ***********************************************************/
// MARK: - DTGFilePaths
/* ***********************************************************/

class DTGFilePaths {
    
    private static let mainDirName = "KalturaDTG"
    private static let itemsDirName = "items"
    
    static let storagePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent(mainDirName, isDirectory: true)
    }()
    
    class var itemsDirUrl: URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true)
    }
    
    static func itemDirUrl(forItemId id: String) -> URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true).appendingPathComponent(id.safeItemPathName(), isDirectory: true)
    }
}

/* ***********************************************************/
// MARK: - ContentManager
/* ***********************************************************/

public class ContentManager: NSObject, DTGContentManager {
    
    /// shared singleton object
    public static let shared: DTGContentManager = ContentManager()
    
    /// Version string
    public static let versionString: String = Bundle(for: ContentManager.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    /// The client tag
    public static let clientTag = "playkit-dtg/ios-\(versionString)"
    /// session id, lives as long as the app is alive.
    let sessionId = UUID()
    /// A custom referrer, used for requesting the play manifest, if no referrer is set app id is used.
    public var referrer: String?
    
    public weak var delegate: ContentManagerDelegate?

    public var storagePath: URL {
        return DTGFilePaths.storagePath
    }
    
    var started = false
    var server = GCDWebServer()
    var serverUrl: URL? {
        return server.isRunning ? server.serverURL : nil
    }
    var serverPort: UInt?
    var startCompletionHandler: (() -> Void)?
    
    // db interface instance
    let db: RealmDB
    
    static let megabyteInBytes: Int64 = 1000000
    /// the minimum free space we need to have in addition to the estimated size, to prevent no disk space issues.
    static let downloadMinimumDiskSpaceInMegabytes = 200
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
    private override init() {
        /// create main directory
        try! FileManager.default.createDirectory(at: DTGFilePaths.storagePath, withIntermediateDirectories: true, attributes: nil)
        
        /// exclude url from from backup
        var url: URL = DTGFilePaths.storagePath
        do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        } catch let error as NSError {
            log.error("Error excluding \(url.lastPathComponent) from backup \(error)");
        }
        
        // initialize db
        self.db = RealmDB()
        super.init()
        // setup log default log level
        #if DEBUG
            let logLevel: XCGLogger.Level = .debug
        #else
            let logLevel: XCGLogger.Level = .info
        #endif
        log.setup(level: logLevel, showLevel: true, showFileNames: true, showLineNumbers: true, showDate: true)
        log.debug("*** ContentManager ***")
    }
    
    private func startServer() throws {
        // start server
        server.addGETHandler(forBasePath: "/", directoryPath: DTGFilePaths.itemsDirUrl.path, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
        try server.start(options: [
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_Port: 0,
            ])

        serverPort = server.port
        
        // Stop the server, then restart it on a fixed port. 
        server.stop()
        server.delegate = self
        try server.start(options: [
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_Port: serverPort!,
            ])        
    }
    
    public func start(completionHandler: (() -> Void)?) throws {
        if started {
            return
        }

        self.startCompletionHandler = completionHandler
        
        try startServer()

        started = true
    }
    
    public func stop() {
        // stop server
        server.stop()
        started = false
    }

    public func startItems(inStates states: DTGItemStartableState...) throws {
        if states.contains(.inProgress) {
            for item in try itemsByState(.inProgress) {
                try startItem(id: item.id)
            }
        }
        if states.contains(.paused) {
            for item in try itemsByState(.paused) {
                try startItem(id: item.id)
            }
        }
        if states.contains(.interrupted) {
            for item in try itemsByState(.interrupted) {
                try startItem(id: item.id)
            }
        }
    }

    public func itemsByState(_ state: DTGItemState) throws -> [DTGItem] {

        return try db.getItems(byState: state)
    }
    
    public func itemById(_ id: String) throws -> DTGItem? {
        return try db.getItem(byId: id)
    }
    
    public func addItem(id: String, url: URL) throws -> DTGItem? {
        if try db.getItem(byId: id) != nil {
            log.error("Item already exists: \(id)")
            return nil
        }
        
        let item = DownloadItem(id: id, url: url)
        try self.add(item: item)

        return item
    }

    public func loadItemMetadata(id: String, preferredVideoBitrate: Int?) throws {
        var item = try findItemOrThrow(id)
        // can only load metadata on item in `.new` state.
        guard item.state == .new else { throw DTGError.invalidState(itemId: id) }
        
        let referrer = (self.referrer == nil ? Bundle.main.bundleIdentifier ?? "" : self.referrer!).data(using: .utf8)?.base64EncodedString() ?? ""
        let requestAdapter = PlayManifestRequestAdapter(url: item.remoteUrl, sessionId: self.sessionId.uuidString, clientTag: ContentManager.clientTag, referrer: referrer, playbackType: "offline")
        let localizer = HLSLocalizer(id: id, url: requestAdapter.adapt(), downloadPath: DTGFilePaths.itemDirUrl(forItemId: id), preferredVideoBitrate: preferredVideoBitrate)
        
        try localizer.loadMetadata()
        try localizer.saveLocalFiles()
        // when localizer finished add the tasks and update the item
        try self.db.set(tasks: localizer.tasks)
        item.state = .metadataLoaded
        item.estimatedSize = localizer.estimatedSize
        item.availableTextTracks = localizer.availableTextTracksInfo
        item.availableAudioTracks = localizer.availableAudioTracksInfo
        item.selectedTextTracks = localizer.selectedTextTracksInfo
        item.selectedAudioTracks = localizer.selectedAudioTracksInfo
        try self.db.updateAfterMetadataLoaded(item: item)
        notifyItemState(item.id, newState: .metadataLoaded, error: nil)
    }
    
    public func startItem(id: String) throws {
        // find in db
        let item = try findItemOrThrow(id)
        
        // for item to start downloading state must be metadataLoaded/paused or inProgress + no active downloader for the selected id.
        guard item.state == .metadataLoaded || item.state == .paused || item.state == .interrupted || (item.state == .inProgress && self.downloaders[id] == nil) else {
            throw DTGError.invalidState(itemId: id)
        }
        
        // check free disk space to make sure we have enough before we start.
        if let freeDiskSpace = ContentManager.getFreeDiskSpaceInBytes() {
            let minimumDiskSpaceInBytes = Int64(ContentManager.downloadMinimumDiskSpaceInMegabytes) * ContentManager.megabyteInBytes
            if let estimatedSize = item.estimatedSize {
                // resuming a downloaded, make sure we have enough space and a we have more that the minimum we allow
                if (item.state == .inProgress || item.state == .interrupted || item.state == .paused) {
                    // for a rare case where we might have that download interrupted serveral times and we downloaded more than the estimate,
                    // use 0 as the new estimate instead of negative number.
                    let resumeEstimatedSize = estimatedSize - item.downloadedSize < 0 ? 0 : estimatedSize - item.downloadedSize
                    if freeDiskSpace <= minimumDiskSpaceInBytes ||
                        freeDiskSpace <= resumeEstimatedSize + minimumDiskSpaceInBytes {
                        throw DTGError.insufficientDiskSpace(freeSpaceInMegabytes: Int(freeDiskSpace/ContentManager.megabyteInBytes))
                    }
                }
                // starting a new download
                else if item.state == .metadataLoaded && freeDiskSpace <= (estimatedSize + minimumDiskSpaceInBytes) {
                    throw DTGError.insufficientDiskSpace(freeSpaceInMegabytes: Int(freeDiskSpace/ContentManager.megabyteInBytes))
                }
            }
        }
        
        // make sure we have tasks to perform
        let tasks = try db.getTasks(forItemId: id)
        guard tasks.count > 0 else {
            log.warning("no tasks for this id")
            // if an item was started and his state allows to start and has no tasks set the state to completed.
            try self.update(itemState: .completed, byId: id)
            return
        }
        
        try self.update(itemState: .inProgress, byId: id)
        
        let downloader = DefaultDownloader(itemId: id, tasks: tasks)
        downloader.delegate = self
        self.downloaders[id] = downloader
        try downloader.start()
    }

    public func pauseItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            log.warning("no downloader for this id")
            return
        }
        // update state, changed before downloader delegate called
        // to make sure every call to db to get item will be with the updated state.
        try self.update(itemState: .paused, byId: downloader.dtgItemId)
        // pause the downloads and remove the downloader
        downloader.pause()
    }

    public func removeItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, cancel
        if let downloader = self.downloaders[id] {
            self.downloaders[id] = nil
            downloader.cancel()
        }
        
        // remove from db
        try db.removeItem(byId: id)
        
        // remove all files
        let itemPath = DTGFilePaths.itemDirUrl(forItemId: id)
        let fileManager = FileManager.default
        var isDir: ObjCBool = true
        if fileManager.fileExists(atPath: itemPath.path, isDirectory:&isDir) {
            if isDir.boolValue {
                // file exists and is a directory
                try fileManager.removeItem(at: itemPath)
            } else {
                // file exists and is not a directory
            }
        } else {
            log.warning("can't remove item files, dir doesn't exist")
        }
        
        // notify state change
        self.notifyItemState(id, newState: .removed, error: nil)
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
    
    public func setup() throws {
        // gets the realm instance, when migration is needed sets up the new scheme and migration block.
        _ = try getRealm()
    }
}

/************************************************************/
// MARK: - GCDWebServerDelegate
/************************************************************/

extension ContentManager: GCDWebServerDelegate {
    
    public func webServerDidStart(_ server: GCDWebServer) {
        self.startCompletionHandler?()
        self.startCompletionHandler = nil
    }
}


/************************************************************/
// MARK: - DownloaderDelegate
/************************************************************/

extension ContentManager: DownloaderDelegate {
    
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64) {
        do {
            
            if downloader.state.value == .cancelled {
                // In case we get a progress update after the download has been canceled we don't want to update it.
                return
            }
            
            // When we receive progress for downloads when downloader is pasued make sure item state is pasued
            // otherwise because the delegate and db are async we can receive an item with state `inProgress` before the change was made.
            let newState = (downloader.state.value == .paused) ? DTGItemState.paused : nil

            let (newSize, estSize) = try self.updateItem(id: downloader.dtgItemId, incrementDownloadSize: bytesWritten, state: newState)
            
            self.delegate?.item(id: downloader.dtgItemId, didDownloadData: newSize, totalBytesEstimated: estSize)
            
        } catch {
            // Remove the downloader, data storage has an issue or is full no need to keep downloading for now.
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask]) {
        log.info("downloading paused")
        self.removeDownloader(withId: downloader.dtgItemId)
        do {
            // Save pasued tasks to db
            try self.db.pauseTasks(tasks)
        } catch {
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloaderDidCancelDownloadTasks(_ downloader: Downloader) {
        // Clear the downloader instance
        self.removeDownloader(withId: downloader.dtgItemId)
        do {
            // Removes all tasks from the db
            try self.db.removeTasks(withItemId: downloader.dtgItemId)
        } catch {
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didFinishDownloading downloadItemTask: DownloadItemTask) {
        do {
            // Remove the task from the db tasks objects
            try self.db.removeTask(downloadItemTask)
        } catch {
            // Remove the downloader, data storage has an issue or is full no need to keep downloading for now.
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didChangeToState newState: DownloaderState) {
        log.debug("downloader state: \(newState.rawValue)")
        if newState == .idle {
            try? self.update(itemState: .completed, byId: downloader.dtgItemId)
            // Remove the downloader, no longer needed
            self.removeDownloader(withId: downloader.dtgItemId)
        } else if newState == .paused {
            do {
                try self.update(itemState: .paused, byId: downloader.dtgItemId)
            } catch {
                // Remove the downloader, data storage has an issue or is full no need to keep downloading for now.
                self.removeDownloader(withId: downloader.dtgItemId)
                self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
            }
        }
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        do {
            switch error {
            case DownloaderError.http(let statusCode, let rootError):
                if statusCode >= 500 {
                    try self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: rootError)
                } else {
                    try self.update(itemState: .failed, byId: downloader.dtgItemId, error: error)
                }
            case DownloaderError.noSpaceLeftOnDevice, DTGError.insufficientDiskSpace:
                try self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: error)
            default: try self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: error)
            }
        } catch {
            // If downloader was already removed don't notify db failure again.
            guard downloaders[downloader.dtgItemId] != nil else { return }
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
}

/************************************************************/
// MARK: - Internal Implementation
/************************************************************/

extension ContentManager {
    
    static func getFreeDiskSpaceInBytes() -> Int64? {
        do {
            let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (systemAttributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value
        } catch {
            return 0
        }
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

private extension ContentManager {
    
    
    func updateItem(id: String, incrementDownloadSize: Int64, state: DTGItemState?) throws -> (newSize: Int64, estSize: Int64) {
        let res = try db.updateItemSize(id: id, incrementDownloadSize: incrementDownloadSize, state: state)
        if let state = state {
            self.notifyItemState(id, newState: state, error: nil)
        }
        return res
    }
    
    func add(item: DownloadItem) throws {
        try db.add(item: item)
        self.notifyItemState(item.id, newState: item.state, error: nil)
    }
    
    func update(itemState: DTGItemState, byId id: String, error: Error? = nil) throws {
        if itemState == .failed {
            try self.removeItem(id: id)
        } else {
            try self.db.updateItemState(id: id, newState: itemState)
        }
        self.notifyItemState(id, newState: itemState, error: error)
    }
    
    @discardableResult
    func findItemOrThrow(_ id: String) throws -> DownloadItem {
        if let item = try db.getItem(byId: id) {
            return item
        } else {
            throw DTGError.itemNotFound(itemId: id)
        }
    }
    
    func notifyItemState(_ id: String, newState: DTGItemState, error: Error? = nil) {
        log.info("item: \(id), state updated, new state: \(newState.asString())")
        DispatchQueue.main.async {
            self.delegate?.item(id: id, didChangeToState: newState, error: error)
        }
    }
    
    func removeDownloader(withId itemId: String) {
        let downloader = self.downloaders[itemId]
        downloader?.invalidateSession()
        self.downloaders[itemId] = nil
    }
}
