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

/// `DownloadItemTask` represents one file to download (could be video, audio or captions)
struct DownloadItemTask {
    let dtgItemId: String
    /// The content url, should be unique!
    let contentUrl: URL
    let type: DownloadItemTaskType
    /// The destination to save the download item to.
    let destinationUrl: URL
    
    let order: Int?
    
    var retry: Int = 1
    var resumeData: Data? = nil
    
    init(dtgItemId: String, contentUrl: URL, type: DownloadItemTaskType, destinationUrl: URL, order: Int?) {
        self.dtgItemId = dtgItemId
        self.contentUrl = contentUrl
        self.type = type
        self.destinationUrl = destinationUrl
        self.order = order
    }
}

enum DownloaderState: String {
    /// Downloader was created but haven't start downloading.
    case new
    /// Downloader is currently downloading items.
    case downloading
    /// Downloader was paused.
    case paused
    /// Downloader finished all download tasks, can add more or stop the session.
    case idle
    /// Downloads were cancelled and the downloader session is unusable at this state.
    case cancelled
}

protocol Downloader: class {
    /// The session identifier, used to restore background sessions and to identify them.
    var sessionIdentifier: String { get }
    
    /// The downloader delegate object.
    var delegate: DownloaderDelegate? { get set }
    
    /// Background completion handler, can be received from application delegate when woken to background.
    /// Should be invoked when `urlSessionDidFinishEvents` is called.
    var backgroundSessionCompletionHandler: (() -> Void)? { get set }
    
    /// The max allowed concurrent download tasks.
    var maxConcurrentDownloadItemTasks: Int { get }
    
    /// The related dtg item id
    var dtgItemId: String { get }
    
    /// The state of the downloader.
    var state: SynchronizedProperty<DownloaderState> { get }
    
    init(itemId: String, tasks: [DownloadItemTask])
    
    /// Starts the download according to the tasks ordering in the queue.
    /// use this only for the initial start.
    func start() throws
    
    /// Used to add more download tasks to the session.
    func addDownloadItemTasks(_ tasks: [DownloadItemTask]) throws
    
    /// Pauses all active downloads. and put the active downloads back in the queue.
    func pause()
    
    /// Cancels all active downloads and invalidates the session.
    func cancel()
    
    /// Invalidate the session. after invalidating the session is not usable anymore.
    func invalidateSession()
    
    /// creates a new background url session replacing current session.
    func refreshSession()
}

protocol DownloaderDelegate: class {
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64)
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask])
    func downloaderDidCancelDownloadTasks(_ downloader: Downloader)
    func downloader(_ downloader: Downloader, didFinishDownloading downloadItemTask: DownloadItemTask)
    func downloader(_ downloader: Downloader, didChangeToState newState: DownloaderState)
    /// Called when downloader failed due to fatal error
    func downloader(_ downloader: Downloader, didFailWithError error: Error)
}
