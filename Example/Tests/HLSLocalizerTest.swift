//
//  HLSLocalizer.swift
//  DownloadToGo_Tests
//
//  Created by Noam Tamim on 03/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
@testable import DownloadToGo


public func eq<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, "", file: file, line: line)
}


class HLSLocalizerTest: XCTestCase {

    let bundleURL = Bundle(for: HLSLocalizerTest.self).bundleURL
    let audioBitrateEstimation = 64000
    
    func localSampleUrl(_ id: String) -> URL {
        return bundleURL.appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("master.m3u8")
    }

    func downloadPath(_ id: String) -> URL {
        return DTGFilePaths.itemDirUrl(forItemId: id)
    }
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func verify(_ hls: HLSLocalizer, 
                duration: Double,
                taskCount: Int,
                estimatedSize: Int64,
                videoBitrate: Int,
                videoHeight: Int? = nil,
                videoWidth: Int? = nil,
                resolution: String? = nil
        ) {

        eq(hls.duration, duration)
        eq(hls.tasks.count, taskCount)
        eq(hls.estimatedSize, estimatedSize)
        eq(hls.selectedVideoStream?.streamInfo.bandwidth, videoBitrate)
        
        if let videoHeight = videoHeight {
            eq(Int(hls.selectedVideoStream?.streamInfo.resolution.height ?? -1), videoHeight)
        }
        if let videoWidth = videoWidth {
            eq(Int(hls.selectedVideoStream?.streamInfo.resolution.width ?? -1), videoWidth)
        }
        if let resolution = resolution {
            eq("\(Int(hls.selectedVideoStream?.streamInfo.resolution.width ?? 0))x\(Int(hls.selectedVideoStream?.streamInfo.resolution.height ?? 0))", resolution)
        }

        //        hlsLoc.selectedAudioStreams
        //        hlsLoc.selectedAudioTracksInfo
        //        hlsLoc.selectedTextStreams
        //        hlsLoc.selectedTextTracksInfo
    }
    
    func load(_ nameOrUrl: String, _ options: DTGSelectionOptions?) -> HLSLocalizer {
        
        let sampleUrl: URL
        if nameOrUrl.hasPrefix("http") {
            sampleUrl = URL(string: nameOrUrl)!
        } else {
            sampleUrl = localSampleUrl(nameOrUrl)
        }
        let id = "whatever"
        let hlsLoc = HLSLocalizer(id: id, url: sampleUrl, downloadPath: downloadPath(id), options: options, audioBitrateEstimation: 64000)
        
        try! hlsLoc.loadMetadata()
        
        func print_properties(mirror: Mirror) {
            for c in mirror.children {
                print("\(c.label ?? "??") = \(c.value)")
            }
        }
        
        print_properties(mirror: Mirror(reflecting: hlsLoc))
        
        return hlsLoc
    }
    
    func testLocalAsset1() {
        let hlsLoc = load("t1", nil)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 6, 
               estimatedSize: 1533726,
               videoBitrate: 488448,
               videoHeight: 360,
               videoWidth: 640
        )
        eq(hlsLoc.availableAudioTracksInfo.count, 4)
    }

    func testLocalAsset2() {
        let options = DTGSelectionOptions()
            .setAudioLanguages(["bul", "eng"])
        let hlsLoc = load("t1", options)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               estimatedSize: 1_935_646,
               videoBitrate: 488_448,
               videoHeight: 360,
               videoWidth: 640
        )
    }
    
    func testLocalAsset3() {
        let options = DTGSelectionOptions()
            .setAudioLanguages(["bul", "eng"])
            .setPreferredVideoWidth(900)
            .setPreferredVideoBitrates([.avc1(900_000)])
        let hlsLoc = load("t1", options)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               estimatedSize: 3227920,
               videoBitrate: 900_000,
               videoHeight: 720,
               videoWidth: 1280
        )
    }
    
    func testLocalAsset4() {
        let options = DTGSelectionOptions()
            .setAudioLanguages(["bul", "eng"])
            .setPreferredVideoWidth(900)
            .setPreferredVideoHeight(700)
        let hlsLoc = load("t1", options)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               estimatedSize: 3227920,
               videoBitrate: 900_000,
               videoHeight: 720,
               videoWidth: 1280
        )
    }
    
    let url_2 = "http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/flavorIds/0_et3i1dux,0_pa4k1rn9/format/applehttp/protocol/http/a.m3u8"
    func testMultiMulti_1() {
        let options = DTGSelectionOptions()
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187, estimatedSize: 95172864, videoBitrate: 1027395, videoHeight: 360, videoWidth: 640)
    }
    
    func testMultiMulti_2() {
        let options = DTGSelectionOptions()
            .setPreferredVideoWidth(700)
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187, estimatedSize: 159528060, videoBitrate: 1722112, resolution: "1280x720")
    }
    
    func testMultiMulti_3() {
        let options = DTGSelectionOptions()
            .setPreferredVideoBitrates([.avc1(1_000_000)])
            .setAllAudioLanguages(true)
            .setTextLanguages(["nl", "en"])
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187+187*2+25*2, estimatedSize: Int64(741.081*(1027395+2*64000)/8), videoBitrate: 1027395, resolution: "640x360")
    }
}
