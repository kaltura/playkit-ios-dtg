//
//  DefaultDownloader.swift
//  Pods
//
//  Created by Gal Orlanczyk on 10/07/2017.
//
//

import Foundation

func ==(lhs: DefaultDownloader, rhs: DefaultDownloader) -> Bool {
    return lhs.sessionIdentifier == rhs.sessionIdentifier
}

enum DownloaderError: Error {
    case downloadAlreadyStarted
    case cannotAddDownloads
}

/// `Downloader` object is responsible for downloading files locally and reporting progres.
class DefaultDownloader: NSObject, Downloader {
    
    /************************************************************/
    // MARK: - Private Properties
    /************************************************************/
    
    /// Holds all the active downloads map of session task and the corresponding download task.
    fileprivate var activeDownloads = [URLSessionDownloadTask: DownloadItemTask]()
    
    fileprivate var downloadURLSession: URLSession!
    
    /// Queue for holding all the download tasks (FIFO)
    fileprivate var downloadItemTasksQueue = Queue<DownloadItemTask>()
    
    fileprivate let synchronizedQueue = DispatchQueue(label: "com.kaltura.dtg.session.synchronizedQueue")
    
    fileprivate var currentTasksCount: Int {
        return synchronizedQueue.sync {
            return self.activeDownloads.count
        }
    }
    
    private var _state: DownloaderState = .new
    
    /************************************************************/
    // MARK: - Downloader Properties
    /************************************************************/
    
    /// The session identifier
    let sessionIdentifier = "com.kaltura.dtg.session-\(UUID().uuidString)"
    
    weak var delegate: DownloaderDelegate?
    
    var backgroundSessionCompletionHandler: (() -> Void)?
    
    let maxConcurrentDownloadItemTasks: Int = 4
    
    let dtgItemId: String
    
    fileprivate(set) var state: DownloaderState {
        get {
            return synchronizedQueue.sync {
                return self._state
            }
        }
        set {
            synchronizedQueue.sync {
                self._state = newValue
                self.delegate?.downloader(self, didChangeToState: newValue)
            }
        }
    }
    
    /************************************************************/
    // MARK: - Initialization
    /************************************************************/
    
    required init(itemId: String, tasks: [DownloadItemTask]) {
        self.dtgItemId = itemId
        super.init()
        self.downloadItemTasksQueue.enqueue(tasks)
        self.setBackgroundURLSession()
    }
}

/************************************************************/
// MARK: - Downloader Methods
/************************************************************/

extension DefaultDownloader {
    
    func start() throws {
        guard self.state == .new else { throw DownloaderError.downloadAlreadyStarted }
        self.state = .downloading
        self.downloadIfAvailable()
    }
    
    func addDownloadItemTasks(_ tasks: [DownloadItemTask]) throws {
        let state = self.state
        guard state == .downloading || state == .idle else {
            print("error: cannot add downloads make sure you started the downloader")
            throw DownloaderError.cannotAddDownloads
        }
        
        if self.downloadItemTasksQueue.count == 0 { // if no downloads were active start downloading
            self.downloadItemTasksQueue.enqueue(tasks)
            self.state = .downloading
            self.downloadIfAvailable()
        } else { // if downloads are active just add more tasks to the queue
            self.downloadItemTasksQueue.enqueue(tasks)
        }
    }
    
    func pause() {
        self.pauseDownloadTasks { (pausedTasks) in
            self.state = .paused
            self.delegate?.downloader(self, didPauseDownloadTasks: pausedTasks)
        }
    }
    
    func cancel() {
        self.cancelDownloadTasks()
        self.state = .cancelled
        self.invalidateSession()
    }
    
    func invalidateSession() {
        self.downloadURLSession.invalidateAndCancel()
    }
    
    func refreshSession() {
        self.setBackgroundURLSession()
        self.state = .new
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

private extension DefaultDownloader {
    
    /// Starts downloading if any tasks are available in the queue and current tasks isn't more than max allowed.
    func downloadIfAvailable() {
        if self.currentTasksCount < self.maxConcurrentDownloadItemTasks && self.downloadItemTasksQueue.count > 0 {
            repeat {
                guard let downloadTask = self.downloadItemTasksQueue.dequeue() else { continue }
                self.start(downloadTask: downloadTask)
            } while self.currentTasksCount < self.maxConcurrentDownloadItemTasks && self.downloadItemTasksQueue.count > 0
        }
    }
    
    func start(downloadTask: DownloadItemTask) {
        let urlSessionDownloadTask: URLSessionDownloadTask
        if let downloadTaskResumeData = downloadTask.resumeData {
            // if we have resume data create a task with the resume data and remove it from the downloadTask
            urlSessionDownloadTask = self.downloadURLSession.downloadTask(withResumeData: downloadTaskResumeData)
        } else {
            urlSessionDownloadTask = self.downloadURLSession.downloadTask(with: downloadTask.contentUrl)
        }
        self.activeDownloads[urlSessionDownloadTask] = downloadTask
        urlSessionDownloadTask.resume()
        print("started download task with identifier: \(urlSessionDownloadTask.taskIdentifier)")
    }
    
    func pauseDownloadTasks(completionHandler: @escaping ([DownloadItemTask]) -> Void) {
        guard self.activeDownloads.count > 0 else {
            completionHandler([])
            return
        }
        var pausedTasks = [DownloadItemTask]()
        
        // make sure to wait for all active downloads to pause by using dispatch queue wait.
        let dispatchGroup = DispatchGroup()
        for (_, _) in self.activeDownloads {
            dispatchGroup.enter()
        }
        for (sessionTask, downloadTask) in self.activeDownloads {
            sessionTask.cancel { (data) in
                var downloadTask = downloadTask
                downloadTask.resumeData = data
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
        for (sessionTask, _) in self.activeDownloads {
            sessionTask.cancel()
        }
        self.activeDownloads.removeAll()
        self.downloadItemTasksQueue.purge()
    }
    
    func setBackgroundURLSession() {
        let backgroundSessionConfiguration = URLSessionConfiguration.background(withIdentifier: self.sessionIdentifier)
        // initialize download url session with background configuration
        self.downloadURLSession = URLSession(configuration: backgroundSessionConfiguration, delegate: self, delegateQueue: nil)
    }
}

/************************************************************/
// MARK: - URLSessionDelegate
/************************************************************/

extension DefaultDownloader: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        // inner retry func
        func retry(downloadTask: URLSessionDownloadTask, resumeData: Data? = nil, receivedError error: NSError) {
            if var downloadItemTask = self.activeDownloads[downloadTask], downloadItemTask.retry > 0 {
                downloadItemTask.retry -= 1
                downloadItemTask.resumeData = resumeData
                self.downloadItemTasksQueue.enqueueAtHead(downloadItemTask)
                self.activeDownloads[downloadTask] = nil
                return
            } else {
                self.cancel()
                self.delegate?.downloader(self, didFailWithError: error)
            }
        }
        
        if let e = error as NSError?, let downloadTask = task as? URLSessionDownloadTask {
            if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode == 503 {
                retry(downloadTask: downloadTask, receivedError: e)
            } else {
                // TODO: handle error (maybe return to the queue? add retry params to tasks?)
                // maybe send progress update with negative amount to substract to amount downloaded?
                if let resumeData = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    print("has resumse data from error")
                    retry(downloadTask: downloadTask, resumeData: resumeData, receivedError: e)
                }
                self.cancel()
                self.delegate?.downloader(self, didFailWithError: e)
                return
            }
        }
        
        if activeDownloads.count == 0 && self.downloadItemTasksQueue.count == 0 {
            self.state = .idle
        } else {
            // take next task if available
            self.downloadIfAvailable()
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let e = error {
            self.delegate?.downloader(self, didFailWithError: e)
        }
    }
}

/************************************************************/
// MARK: - URLSessionDownloadDelegate
/************************************************************/

extension DefaultDownloader: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        print("task identifier = \(downloadTask.taskIdentifier)")
        print("active task identifiers = \(self.activeDownloads.map { $0.0.taskIdentifier })")
        guard let downloadItemTask = self.activeDownloads[downloadTask] else {
            print("error: no active download for this task")
            return
        }
        
        do {
            // if the file exists for some reason, rewrite it.
            if fileManager.fileExists(atPath: downloadItemTask.destinationUrl.path) {
                print("warning: file exists rewriting")
                try fileManager.removeItem(at: downloadItemTask.destinationUrl)
            }
            try fileManager.moveItem(at: location, to: downloadItemTask.destinationUrl)
            // remove the download task from the active downloads
            self.activeDownloads[downloadTask] = nil
            self.delegate?.downloader(self, didFinishDownloading: downloadItemTask)
        } catch let error {
            print("error: \(error)")
            self.delegate?.downloader(self, didFailWithError: error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.delegate?.downloader(self, didProgress: bytesWritten)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        // if resumed a download remove the resumeData object from that download task.
        guard var activeDownloadTask = self.activeDownloads[downloadTask] else { return }
        activeDownloadTask.resumeData = nil
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let backgroundSessionCompletionHandler = self.backgroundSessionCompletionHandler {
            self.backgroundSessionCompletionHandler = nil
            backgroundSessionCompletionHandler()
        }
        print("all current background tasks are finished")
    }
}
