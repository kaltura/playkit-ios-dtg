//
//  FairPlayDTG.swift
//  DownloadToGo_Example
//
//  Created by Noam Tamim on 30/01/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import PlayKit
import AVFoundation

fileprivate let DummyURL = URL(string: "https://cdnapisec.kaltura.com/p/2222401/playManifest/entryId/1_atlb2z4i/format/applehttp/protocol/https/dummy.m3u8")!

public class FairPlayLicenseFetcher: NSObject {
    
    /// The AVAssetDownloadURLSession to use for managing AVAssetDownloadTasks.
    fileprivate var assetDownloadURLSession: AVAssetDownloadURLSession!
    
    var localAssetsManager: LocalAssetsManager
    
    public init(localAssetsManager: LocalAssetsManager) {
        
        self.localAssetsManager = localAssetsManager
        
        super.init()
        
        // Create the configuration for the AVAssetDownloadURLSession.
        let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "FakeDownloader")
        
        // Create the AVAssetDownloadURLSession using the configuration.
        assetDownloadURLSession = AVAssetDownloadURLSession(configuration: backgroundConfiguration, assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }
    
    /// Triggers the initial AVAssetDownloadTask for a given Asset.
    public func start(id: String, media : PKMediaSource) -> Bool {
        
        // Verify this is a FairPlay source
        guard (media.drmData?.first as? FairPlayDRMParams) != nil else {
            print("ERROR: Input MediaSource is not FairPlay") // TODO use log
            return false
        }
        
//        guard let url = ContentManager.shared.serverUrl?.appendingPathComponent("~~FPS~~/\(id).m3u8") else {
//            print("ERROR: No server URL") // TODO use log
//            return false
//        }

        
//        guard let url = URL(string: "https://kgit.html5video.org/dummy-fps.php/\(id).m3u8?x=1") else { 
//            print("ERROR: No server URL") // TODO use log
//            return false
//        }
        
        let url = DummyURL
        
        let asset = AVURLAsset(url: url)
        localAssetsManager.prepareForDownload(asset: asset, mediaSource: media, assetId: "entry-\(id)")
        
        if #available(iOS 10.0, *) {
            guard let task = assetDownloadURLSession.makeAssetDownloadTask(asset: asset, assetTitle: "FPS-\(media.id)",  assetArtworkData: nil, options: nil) else {
                fatalError("Failed to create download task")
            }
            task.resume()
        } else {
            fatalError("Not available")
        }
        
        
        return true
    }
}

extension FairPlayLicenseFetcher: AVAssetDownloadDelegate {
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        if let error = error as NSError? {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                break
            case (NSURLErrorDomain, NSURLErrorUnknown):
                fatalError("Downloading HLS streams is not supported in the simulator.")
                
            default:
                fatalError("An unexpected error occured \(error.domain)")
            }
            
            return
        }
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
    }
}


