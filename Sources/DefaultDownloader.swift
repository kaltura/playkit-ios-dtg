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
import PlayKitUtils

func ==(lhs: DefaultDownloader, rhs: DefaultDownloader) -> Bool {
    return lhs.sessionIdentifier == rhs.sessionIdentifier
}

public enum DownloaderError: Error {
    case downloadAlreadyStarted
    case cannotAddDownloads
    case http(statusCode: Int, rootError: NSError)
    case noSpaceLeftOnDevice
}

// In iOS 12+, sometimes cancel(byProducingResumeData:) returns an invalid resume
// data. The blob returned is very small (around 160 bytes; a valid blob is a few
// kbs). The workaround is in two places: when receiving a blob smaller than 200
// bytes, don't save it; when loading a blob, if it's smaller than 200 bytes don't
// use it. The latter makes sure that if the db is already polluted with bad blobs
// we'll still be able to resume. 
// When there's no resume data, we resume by downloading the chunk again, from scratch.
// This is not too bad because chunks are relatively small.
fileprivate let invalidResumeDataSize = 200

/// `Downloader` object is responsible for downloading files locally and reporting progres.
class DefaultDownloader: NSObject, Downloader {
    
    /************************************************************/
    // MARK: - Private Properties
    /************************************************************/
    
    private var blockNewTasks = false
    
    /// Holds all the active downloads map of session task and the corresponding download task.
    private var activeDownloads = [URLSessionDownloadTask: DownloadItemTask]()
    
    private lazy var downloadURLSession: URLSession? = createSession()
    
    /// Queue for holding all the download tasks (FIFO)
    private var downloadItemTasksQueue = Queue<DownloadItemTask>()
    
    private let synchronizedQueue = DispatchQueue(label: "com.kaltura.dtg.session.synchronizedQueue")
    
    /// Progress updates are throttled as to ensure Realm isn't overloaded with write calls.
    private var lastProgressRefreshTime: Date = Date()
    /// The duration to wait before allowing forwarding a progress update.
    private let progressUpdateThrottle: Double = 0.2
    /// Any throttled progress is stored locally until the throttle permits a subsequent update.
    private var throttledBytesWritten: Int64 = 0
    
    private var currentTasksCount: Int {
        return synchronizedQueue.sync {
            return self.activeDownloads.count
        }
    }
    
    
    /************************************************************/
    // MARK: - Downloader Properties
    /************************************************************/
    
    /// The session identifier
    let sessionIdentifier = "com.kaltura.dtg.session-\(UUID().uuidString)"
    
    weak var delegate: DownloaderDelegate?
    
    var backgroundSessionCompletionHandler: (() -> Void)? {
        didSet {
            if backgroundSessionCompletionHandler != nil {
                self.downloadIfAvailable()
            }
        }
    }
    
    let maxConcurrentDownloadItemTasks: Int = 4
    
    let dtgItemId: String
    
    private(set) var state = SynchronizedProperty<DownloaderState>(initialValue: .new)
    
    /************************************************************/
    // MARK: - Initialization
    /************************************************************/
    required init(itemId: String, tasks: [DownloadItemTask]) {
        self.dtgItemId = itemId
        super.init()
        self.downloadItemTasksQueue.enqueue(tasks)
        self.state.onChange { [weak self] (state) in
            guard let self = self else { return }
            self.delegate?.downloader(self, didChangeToState: state)
        }
    }
    
    private func createSession() -> URLSession {
        let backgroundSessionConfiguration = URLSessionConfiguration.background(withIdentifier: self.sessionIdentifier)
        return URLSession(configuration: backgroundSessionConfiguration, delegate: self, delegateQueue: nil)
    }

    deinit {
        self.invokeBackgroundSessionCompletionHandler()
    }
}

/************************************************************/
// MARK: - Downloader Methods
/************************************************************/

extension DefaultDownloader {
    
    func start() throws {
        blockNewTasks = false
        
        guard self.state.value == .new else { throw DownloaderError.downloadAlreadyStarted }
        self.state.value = .downloading
        self.downloadIfAvailable()
    }
    
    func addDownloadItemTasks(_ tasks: [DownloadItemTask]) throws {
        
        let state = self.state.value
        guard state == .downloading else {
            log.error("cannot add downloads make sure you started the downloader")
            throw DownloaderError.cannotAddDownloads
        }
        
        if self.downloadItemTasksQueue.count == 0 { // if no downloads were active start downloading
            self.downloadItemTasksQueue.enqueue(tasks)
            self.state.value = .downloading
            self.downloadIfAvailable()
        } else { // if downloads are active just add more tasks to the queue
            self.downloadItemTasksQueue.enqueue(tasks)
        }
    }
    
    func pause() {
        self.blockNewTasks = true

        self.pauseDownloadTasks { (pausedTasks) in
            self.state.value = .paused
            self.delegate?.downloader(self, didPauseDownloadTasks: pausedTasks)
        }
    }
    
    func cancel() {
        self.blockNewTasks = true
        
        // Invalidate the session before canceling, so that no new tasks will start
        self.invalidateSession()
        self.cancelDownloadTasks()
        self.state.value = .cancelled
    }
    
    func invalidateSession() {
        downloadURLSession?.invalidateAndCancel()
        downloadURLSession = nil
    }
    
    func refreshSession() {
        self.downloadURLSession = createSession()
        self.state.value = .new
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

private extension DefaultDownloader {
    
    /// Starts downloading if any tasks are available in the queue and current tasks isn't more than max allowed.
    func downloadIfAvailable() {
        if blockNewTasks {
            return
        }
        
        while self.currentTasksCount < self.maxConcurrentDownloadItemTasks && self.downloadItemTasksQueue.count > 0 {
            guard let downloadTask = self.downloadItemTasksQueue.dequeue() else { continue }
            self.start(downloadTask: downloadTask)
        }
    }
    
    func start(downloadTask: DownloadItemTask) {
        
        // Validate that the downloadURLSession wasn't invalidated
        guard let session = self.downloadURLSession else {
            log.debug("Can't start downloading, the session has been invalidated")
            return
        }
        
        let newTask: URLSessionDownloadTask
        
        if let resumeData = downloadTask.resumeData, resumeData.count >= invalidResumeDataSize {
            // if we have resume data create a task with the resume data and remove it from the downloadTask
            newTask = session.downloadTask(withResumeData: resumeData)
        } else {
            var req = URLRequest(url: downloadTask.contentUrl)
            req.addValue(ContentManager.userAgent, forHTTPHeaderField: "user-agent")
            newTask = session.downloadTask(with: req)
        }
        
        self.activeDownloads[newTask] = downloadTask
        newTask.resume()
        log.debug("Started download task with identifier: \(newTask.taskIdentifier)")
    }
    
    func pauseDownloadTasks(completionHandler: @escaping ([DownloadItemTask]) -> Void) {
        
        guard self.activeDownloads.count > 0 else {
            completionHandler([])
            return
        }
        var pausedTasks = [DownloadItemTask]()
        
        // make sure to wait for all active downloads to pause by using dispatch queue wait.
        let dispatchGroup = DispatchGroup()
        
        for (sessionTask, downloadTask) in self.activeDownloads {
            dispatchGroup.enter()
            sessionTask.cancel { (data) in
                log.verbose("Resume data: \(data?.base64EncodedString() ?? "-")")
                var downloadTask = downloadTask
                
                if data?.count ?? 0 >= invalidResumeDataSize {
                    downloadTask.resumeData = data
                }
                
                pausedTasks.append(downloadTask)
                dispatchGroup.leave()
            }
        }
        
        // waits for all active download tasks to cancel
        dispatchGroup.notify(queue: DispatchQueue.global()) {
            self.invalidateSession()
            self.downloadItemTasksQueue.purge()
            self.activeDownloads.removeAll()
            completionHandler(pausedTasks)
        }
    }
    
    func cancelDownloadTasks() {
        guard self.activeDownloads.count > 0 else { return }
        // Remove all items in the queue before canceling the active ones
        self.downloadItemTasksQueue.purge()
        for (sessionTask, _) in self.activeDownloads {
            sessionTask.cancel()
        }
        self.activeDownloads.removeAll()
    }
}

/************************************************************/
// MARK: - URLSessionDelegate
/************************************************************/

extension DefaultDownloader: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        func cancel(with error: Error?) {
            if self.state.value == .cancelled {
                return
            }
            self.cancel()
            if let e = error {
                self.failed(with: e)
            }
        }
        
        // inner retry func
        func retry(downloadTask: URLSessionDownloadTask, resumeData: Data? = nil, receivedError error: Error) {
            if var downloadItemTask = self.activeDownloads[downloadTask], downloadItemTask.retry > 0 {
                downloadItemTask.retry -= 1
                downloadItemTask.resumeData = resumeData
                self.downloadItemTasksQueue.enqueueAtHead(downloadItemTask)
                self.activeDownloads[downloadTask] = nil
                return
            } else {
                cancel(with: error)
            }
        }
        
        if let e = error as NSError?, let downloadTask = task as? URLSessionDownloadTask {
            // if cancelled no need to handle error
            guard e.domain != NSURLErrorDomain || e.code != NSURLErrorCancelled else { return }
            
            if e.domain == NSPOSIXErrorDomain && e.code == 28 {
                cancel(with: DownloaderError.noSpaceLeftOnDevice)
            } else {
                // if http response type and error code is 503 retry
                if let httpResponse = task.response as? HTTPURLResponse {
                    let httpError = DownloaderError.http(statusCode: httpResponse.statusCode, rootError: e)
                    if httpResponse.statusCode >= 500 {
                        retry(downloadTask: downloadTask, receivedError: httpError)
                    } else {
                        cancel(with: e)
                    }
                } else {
                    if let resumeData = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                        log.debug("has resumse data from error, retrying")
                        retry(downloadTask: downloadTask, resumeData: resumeData, receivedError: e)
                    } else {
                        cancel(with: e)
                    }
                }
            }
            return
        }
        
        if activeDownloads.count == 0 && self.downloadItemTasksQueue.count == 0 {
            self.state.value = .idle
            self.invokeBackgroundSessionCompletionHandler()
        } else {
            // make sure there is enough disk space to keep downloading otherwise cancel the download with interruption.
            let allowedFreeDiskSpace = ContentManager.megabyteInBytes * Int64(ContentManager.downloadMinimumDiskSpaceInMegabytes)
            if let freeDiskSpace = ContentManager.getFreeDiskSpaceInBytes(), freeDiskSpace <= allowedFreeDiskSpace {
                cancel(with: DTGError.insufficientDiskSpace(freeSpaceInMegabytes: Int(freeDiskSpace / ContentManager.megabyteInBytes)))
            } else {
                // take next task if available
                self.downloadIfAvailable()
            }
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let e = error {
            self.failed(with: e)
        }
    }
}

/************************************************************/
// MARK: - URLSessionDownloadDelegate
/************************************************************/

extension DefaultDownloader: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        log.debug("active task identifiers = \(self.activeDownloads.map { $0.0.taskIdentifier })")
        log.debug("task finished, identifier = \(downloadTask.taskIdentifier)")
        guard let downloadItemTask = self.activeDownloads[downloadTask] else {
            log.debug("no active download for this task")
            return
        }
        
        // Forward any previously-throttled download progress
        if throttledBytesWritten > 0 {
            self.delegate?.downloader(self, didProgress: throttledBytesWritten)
            throttledBytesWritten = 0
        }
        
        do {
            // if the file exists for some reason, rewrite it.
            if fileManager.fileExists(atPath: downloadItemTask.destinationUrl.path) {
                log.warning("did finish downloading, file exists at location, rewriting")
                try fileManager.removeItem(at: downloadItemTask.destinationUrl)
            }
            try fileManager.moveItem(at: location, to: downloadItemTask.destinationUrl)
            // remove the download task from the active downloads
            self.activeDownloads[downloadTask] = nil
            self.delegate?.downloader(self, didFinishDownloading: downloadItemTask)
        } catch let error {
            log.error("error: \(error)")
            self.failed(with: error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Only report progress updates if the throttle permits
        guard isProgressUpdatePermitted() else {
            throttledBytesWritten += bytesWritten
            return
        }
        self.delegate?.downloader(self, didProgress: bytesWritten + throttledBytesWritten)
        lastProgressRefreshTime = Date()
        throttledBytesWritten = 0
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        // if resumed a download remove the resumeData object from that download task.
        guard var activeDownloadTask = self.activeDownloads[downloadTask] else { return }
        activeDownloadTask.resumeData = nil
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        self.downloadIfAvailable()
        if self.activeDownloads.count > 0 && self.downloadItemTasksQueue.count == 0 {
            self.invokeBackgroundSessionCompletionHandler()
        }
        log.debug("all current enqueued background tasks are delivered")
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

private extension DefaultDownloader {
    
    func invokeBackgroundSessionCompletionHandler() {
        if let backgroundSessionCompletionHandler = self.backgroundSessionCompletionHandler {
            self.backgroundSessionCompletionHandler = nil
            DispatchQueue.main.async {
                log.info("backgroundSessionCompletionHandler will invoke")
                backgroundSessionCompletionHandler()
            }
        }
    }
    
    func failed(with error: Error) {
        log.error("failed downloading, error: \(error.localizedDescription)")
        self.invokeBackgroundSessionCompletionHandler()
        self.delegate?.downloader(self, didFailWithError: error)
    }
    
    func isProgressUpdatePermitted() -> Bool {
        return Date() > lastProgressRefreshTime + progressUpdateThrottle
    }
}

