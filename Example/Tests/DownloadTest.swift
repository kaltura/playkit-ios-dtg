//
//  DownloadTest.swift
//  DownloadToGo_Tests
//
//  Created by Noam Tamim on 04/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
@testable import DownloadToGo

import PlayKit


class DownloadTest: XCTestCase, ContentManagerDelegate {
    
    var expectation: XCTestExpectation?
    var id: String! // assigned in setUp() and removed in tearDown()
    var downloaded = false
    
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?) {
        print(id, "\(Double(totalBytesDownloaded)/1024/1024) / \(Double(totalBytesEstimated ?? -1)/1024/1024)")
    }
    
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?) {
        
        print("QQQ item \(id) moved to state \(newState)")

        if let selfId = self.id {
            if newState == .completed {
                assert(id == selfId, "Id doesn't match")
                print("QQQ item \(id) completed")
                downloaded = true
                expectation?.fulfill()
            }
        } else {
            // setUp
            assert(newState == .removed)
            print("QQQ Removed \(id) in setUp()")
        }
    }
    
    let cm = ContentManager.shared
    
    func waitForDownload(_ timeout: TimeInterval = 300) {
        if let e = expectation {
            wait(for: [e], timeout: timeout)
            eq(item().state, DTGItemState.completed)
            XCTAssert(downloaded, "Not downloaded")
        }
    }
    
    override func setUp() {
        
        self.id = nil
        cm.delegate = self
        try! cm.start { 
            print("QQQ started dtg")
        }

        for s in DTGItemState.allCases {
            for i in try! cm.itemsByState(s) {
                try! cm.removeItem(id: i.id)
                print("QQQ removed leftover item \(i.id)")
            }
        }
        
    }
    
    override func tearDown() {
        cm.delegate = nil
        cm.stop()
    }
    
    func item(_ id: String) -> DTGItem? {
        if let item = try! cm.itemById(id) {
            return item
        }
        XCTFail("No item")
        return nil
    }
    
    func item() -> DTGItem {
        return self.item(self.id)!
    }
    
    func startItem() {
        expectation = XCTestExpectation(description: "Download item")
        try! cm.startItem(id: self.id)
    }
    
    func newItem(_ url: String, _ function: String = #function) {
        var id = function
        id.removeSubrange(id.range(of: "()")!)
        
        self.id = id
        
        print("QQQ new item with id=\(id)")

        try! cm.addItem(id: id, url: URL(string: url)!)
    }
    
    func removeItem() {
        try! cm.removeItem(id: id)
    }
    
    func loadItem(_ options: DTGSelectionOptions?) {
        try! cm.loadItemMetadata(id: self.id, options: options)
    }
    
    func allLangs() -> DTGSelectionOptions {
        return DTGSelectionOptions().setAllTextLanguages().setAllAudioLanguages()
    }
    
    func basic() -> DTGSelectionOptions {
        return DTGSelectionOptions()
    }
    
    func localEntry() -> PKMediaEntry {
        return PKMediaEntry(id, sources: [PKMediaSource(id, contentUrl: try! cm.itemPlaybackUrl(id: id))])
    }
    
    func playItem(audioLangs: [String] = [], textLangs: [String] = []) {
        let player = PlayKitManager.shared.loadPlayer(pluginConfig: nil)
        
        let canPlay = XCTestExpectation(description: "canPlay \(id!)")
        let tracks = XCTestExpectation(description: "tracks for \(id!)")
        
        player.addObserver(self, event: PlayerEvent.error) { (e) in
            print("QQQ Player error: \(e.error)")
        }
        
        player.addObserver(self, event: PlayerEvent.tracksAvailable) { (e) in
        
            if let tracks = e.tracks {
                let textTracks = tracks.textTracks?.map{ $0.language ?? "??" } ?? []
                let audioTracks = tracks.audioTracks?.map{ $0.language ?? "??" } ?? []
                print("QQQ tracks for \(self.id!):", audioTracks, textTracks)

                for lang in audioLangs {
                    XCTAssert(audioTracks.contains(lang), "\(self.id!): \(audioTracks) does not contain \(lang)")
                }
                for lang in textLangs {
                    XCTAssert(textTracks.contains(lang), "\(self.id!): \(textTracks) does not contain \(lang)")
                }
            }
            tracks.fulfill()
        }
        
        player.addObserver(self, event: PlayerEvent.canPlay) { (e) in
            canPlay.fulfill()
        }
        
        let entry = localEntry()
        print("QQQ prepare \(entry)")
        player.prepare(MediaConfig(mediaEntry: entry))
        
        
        
        //        player.addObserver(self, event: PlayerEvent.playheadUpdate) { (e) in
        //            if let time = e.currentTime, time.doubleValue > 10 {
        //                played.fulfill()
        //            } 
        //        }
        //        
        //        print("QQQ start to play")
        //        player.play()
        //        
        wait(for: [canPlay, tracks], timeout: 3)
        //        print("QQQ waited for playback")
        
        player.destroy()
        
    }
    
    func testBasicDownload_1() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(basic())
        
        eq(item().estimatedSize, 47197225)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 47229736)
        
        playItem()
        
        removeItem()
    }
    
    func testBasicDownload_2() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(allLangs())
        
        eq(item().estimatedSize, 59_054_521)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 60_758_276)
        
        playItem(audioLangs: ["en", "es"], textLangs: ["en", "ru", "nl"])

        removeItem()
}
    
    func testBasicDownload_3() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(allLangs().setPreferredVideoWidth(2000))
        
        eq(item().estimatedSize, 171_385_356)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 168_808_644)
        
        playItem(audioLangs: ["en", "es"], textLangs: ["en", "ru", "nl"])

        removeItem()
    }
    
    func testHEVC_1() {
        newItem("https://cdnapisec.kaltura.com/p/2215841/sp/2215841/playManifest/entryId/1_w9zx2eti/flavorIds/1_r6q0xdb6,1_yq8tg3pq,1_1obpcggb,1_huc2wn1a,1_yyuvftfz,1_3f4sp5qu,1_1ybsfwrp,1_1xdbzoa6,1_k16ccgto,1_djdf6bk8/deliveryProfileId/19201/protocol/https/format/applehttp/a.m3u8")
        loadItem(allLangs())
        
        eq(item().estimatedSize, Int64(883.148*(456999+64000)/8))
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 63_101_824)
        
        playItem()

        removeItem()
    }
    
    func testMultiAESKey() {
        newItem("https://noamtamim.com/random/hls/test-enc-aes/multi.m3u8")
        loadItem(nil)
        
        eq(item().estimatedSize, Int64(598.0333259999995*1000000/8))
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 78_614_704)
        
        playItem()

        removeItem()
    }
}

