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
    
    func verify(hls: HLSLocalizer, 
                duration: Double,
                taskCount: Int,
                estimatedSize: Int64,
                videoBitrate: Int,
                videoHeight: Int,
                videoWidth: Int
        ) {

        eq(hls.duration, duration)
        eq(hls.tasks.count, taskCount)
        eq(hls.estimatedSize, estimatedSize)
        eq(hls.selectedVideoStream?.streamInfo.bandwidth, videoBitrate)
        eq(Int(hls.selectedVideoStream?.streamInfo.resolution.height ?? -1), videoHeight)
        eq(Int(hls.selectedVideoStream?.streamInfo.resolution.width ?? -1), videoWidth)

        //        hlsLoc.selectedAudioStreams
        //        hlsLoc.selectedAudioTracksInfo
        //        hlsLoc.selectedTextStreams
        //        hlsLoc.selectedTextTracksInfo
    }
    
    func localLoad(_ id: String, _ options: DTGSelectionOptions? = nil) -> HLSLocalizer {
        
        let hlsLoc = HLSLocalizer(id: id, url: localSampleUrl(id), downloadPath: downloadPath(id), options: options, audioBitrateEstimation: 64000)
        
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
        let hlsLoc = localLoad("t1")
        verify(hls: hlsLoc, 
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
        let hlsLoc = localLoad("t1", options)
        verify(hls: hlsLoc, 
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
        let hlsLoc = localLoad("t1", options)
        verify(hls: hlsLoc, 
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
        let hlsLoc = localLoad("t1", options)
        verify(hls: hlsLoc, 
               duration: 25.12,
               taskCount: 18, 
               estimatedSize: 3227920,
               videoBitrate: 900_000,
               videoHeight: 720,
               videoWidth: 1280
        )
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
    }

}
