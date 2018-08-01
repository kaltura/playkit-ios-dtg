//
//  HLSLocalizerTests.swift
//  DownloadToGo
//
//  Created by Gal Orlanczyk on 26/07/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Quick
import Nimble
@testable import DownloadToGo

class HLSLocalizerTests: QuickSpec {
    
    override func spec() {
        describe("HLSLocalizerTests") {
            
            let id = "test"
            let bundleURL = Bundle(for: type(of: self)).bundleURL
            let url = bundleURL.appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("SampleHLS", isDirectory: true)
                .appendingPathComponent("master.m3u8")
            let downloadPath = DTGFilePaths.itemDirUrl(forItemId: id)
            
            let localizer = HLSLocalizer(id: id, url: url, downloadPath: downloadPath, preferredVideoBitrate: nil, audioBitrateEstimation: 64000)
            
            it("can localize hls m3u8 index file") {
                try! localizer.loadMetadata()
                let tasks = localizer.tasks
                // the sample hls provided has 30 media segments in total make sure it is the same
                expect(tasks.count).to(equal(30))
                for task in tasks {
                    let contentFileName = task.contentUrl.absoluteString.md5()
                    // test file names are ok
                    expect(tasks.contains { $0.destinationUrl.deletingPathExtension().lastPathComponent == contentFileName }).to(beTrue())
                    let expectedDestinationUrl = downloadPath.appendingPathComponent(task.type.asString(), isDirectory: true)
                        .appendingPathComponent(task.contentUrl.absoluteString.md5())
                        .appendingPathExtension(task.contentUrl.pathExtension)
                    // test destination url is ok
                    expect(task.destinationUrl.absoluteString).to(equal(expectedDestinationUrl.absoluteString))
                }
            }
            
            it("can save to to local file system") {
                try! localizer.saveLocalFiles()
                try! FileManager.default.removeItem(at: DTGFilePaths.itemDirUrl(forItemId: id))
            }
        }
    }
}
