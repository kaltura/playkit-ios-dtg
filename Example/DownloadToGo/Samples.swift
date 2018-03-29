//
//  Samples.swift
//  DownloadToGo_Example
//
//  Created by Noam Tamim on 29/03/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import M3U8Kit

func extractAvailableLanguages(masterUrl: URL) throws -> (audio: [String], text: [String]) {
    let master = try M3U8MasterPlaylist(contentOf: masterUrl)
    guard let mediaList = master.xMediaList else {return ([], [])}
    
    var audio = [String]()
    var text = [String]()
    
    if let list = mediaList.audio() {
        for i in 0 ..< list.count {
            audio.append(list.xMedia(at: i).language())
        }
    }
    
    if let list = mediaList.subtitle() {
        for i in 0 ..< list.count {
            text.append(list.xMedia(at: i).language())
        }
    }
    
    return (audio, text)
}



