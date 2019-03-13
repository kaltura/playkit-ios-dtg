//
//  HLSLocalizer.swift
//  DownloadToGo_Tests
//
//  Created by Noam Tamim on 03/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
@testable import DownloadToGo


public func eq<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message, file: file, line: line)
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
                videoBitrate: Int,
                estimatedSize: Double,
                videoHeight: Int? = nil,
                videoWidth: Int? = nil,
                resolution: String? = nil
        ) {

        eq(hls.duration, duration)
        eq(hls.tasks.count, taskCount)
        eq(hls.selectedVideoStream?.streamInfo.bandwidth, videoBitrate)
        eq(hls.estimatedSize, Int64(estimatedSize))
        
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
            print("print_properties (hlsLoc)")
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
               videoBitrate: 488448, 
               estimatedSize: 1533726,
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
               videoBitrate: 488_448, 
               estimatedSize: 1_935_646,
               videoHeight: 360,
               videoWidth: 640
        )
    }
    
    func testLocalAsset3() {
        let options = DTGSelectionOptions()
            .setAudioLanguages(["bul", "eng"])
            .setMinVideoWidth(900)
            .setMinVideoBitrate(.avc1, 900_000)
        let hlsLoc = load("t1", options)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               videoBitrate: 900_000, 
               estimatedSize: 3227920,
               videoHeight: 720,
               videoWidth: 1280
        )
    }
    
    func testLocalAsset4() {
        let options = DTGSelectionOptions()
            .setAudioLanguages(["bul", "eng"])
            .setMinVideoWidth(900)
            .setMinVideoHeight(700)
        let hlsLoc = load("t1", options)
        verify(hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               videoBitrate: 900_000, 
               estimatedSize: 3227920,
               videoHeight: 720,
               videoWidth: 1280
        )
    }
    
    
    func testLocalAssetHEVC_1() {
        let options = DTGSelectionOptions()
        options.setMinVideoWidth(1280)
        let hls = load("t2", options)
        verify(hls, duration: 883.148, taskCount: 93, videoBitrate: 1400032, estimatedSize: 883.148*1400032/8, resolution: "1280x544")
    }
    
    func testLocalAssetHEVC_2() {
        let options = DTGSelectionOptions()
        options.allowInefficientCodecs = true
        options.setMinVideoWidth(1280)
        let hls = load("t2", options)
        verify(hls, duration: 883.148, taskCount: 93, videoBitrate: 781707, estimatedSize: 883.148*781707/8, resolution: "1280x544")
    }

    
    let url_2 = "http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/flavorIds/0_et3i1dux,0_pa4k1rn9/format/applehttp/protocol/http/a.m3u8"
    func testMultiMulti_1() {
        let options = DTGSelectionOptions()
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187, videoBitrate: 1027395, estimatedSize: 95172864, videoHeight: 360, videoWidth: 640)
    }
    
    func testMultiMulti_2() {
        let options = DTGSelectionOptions()
            .setMinVideoWidth(700)
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187, videoBitrate: 1722112, estimatedSize: 159528060, resolution: "1280x720")
    }
    
    func testMultiMulti_3() {
        let options = DTGSelectionOptions()
            .setMinVideoBitrate(.avc1, 1_000_000)
            .setAllAudioLanguages(true)
            .setTextLanguages(["nl", "en"])
        let hls = load(url_2, options)
        
        verify(hls, duration: 741.081, taskCount: 187+187*2+25*2, videoBitrate: 1027395, estimatedSize: 741.081*(1027395+2*64000)/8, resolution: "640x360")
    }
    
    let url_3 = "https://cdnapisec.kaltura.com/p/2215841/sp/2215841/playManifest/entryId/1_w9zx2eti/flavorIds/1_r6q0xdb6,1_yq8tg3pq,1_1obpcggb,1_huc2wn1a,1_yyuvftfz,1_3f4sp5qu,1_1ybsfwrp,1_1xdbzoa6,1_k16ccgto,1_djdf6bk8/deliveryProfileId/19201/protocol/https/format/applehttp/a.m3u8"
    func testHEVC_1() {
        let options = DTGSelectionOptions()
        options.setAllTextLanguages()
        options.setAllAudioLanguages()
        let hls = load(url_3, options)
        
        verify(hls, duration: 883.148, taskCount: 2*92, videoBitrate: 456999, estimatedSize: 883.148*(456999+64000)/8, resolution: "640x272")
    }
    
    let url_4 = "https://noamtamim.com/random/hls/test-enc-aes/multi.m3u8"
    func testMultiAESKey() {
        let options = DTGSelectionOptions()
        let hls = load(url_4, options)
        verify(hls, duration: 598.0333259999995, taskCount: 2*149, videoBitrate: 1000000, estimatedSize: 598.0333259999995*1000000/8, resolution: "640x360")
    }
}
