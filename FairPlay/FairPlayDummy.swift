//
//  FairPlayDummy.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 13/02/2018.
//

import Foundation
import GCDWebServer

class FairPlayDummy {
    public static func addHandler(server: GCDWebServer) {
        server.addHandler(forMethod: "GET", pathRegex: "/~~FPS~~/\\w+\\..+", request: GCDWebServerDataRequest.self, asyncProcessBlock: { (request, callback) in
            if let callback = callback, let request = request as? GCDWebServerDataRequest {
                FairPlayDummy(client: callback, request: request).startLoading()
            }
        })
    }
    
    let respond: GCDWebServerCompletionBlock
    let request: GCDWebServerDataRequest
    
    init(client: @escaping GCDWebServerCompletionBlock, request: GCDWebServerDataRequest) {
        self.respond = client
        self.request = request
    }
    
    func startLoading() {
        // start responding to client
        
        guard let file = request.url?.lastPathComponent else {
            return
        }
        
        let split = file.split(separator: ".")
        
        guard let id = split.first, let ext = split.last else {
            return
        }
        
        
        
        
        switch ext {
        case "m3u8":
            sendMaster(id)
        case "media":
            sendMedia(id)
        case "ts":
            sendTS()
        default:
            return
        }
    }
    
    func sendMaster(_ id: String.SubSequence) {
        
        let str = """
#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=44531,RESOLUTION=32x32
\(id).media
"""
        
        respond(GCDWebServerDataResponse(data: str.data(using: .utf8), contentType: "application/x-mpegURL"))
    }
    
    func sendMedia(_ id: String.SubSequence) {
        let str = """
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-ALLOW-CACHE:YES
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://entry-\(id)",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"
#EXT-X-VERSION:5
#EXT-X-MEDIA-SEQUENCE:1
#EXTINF:0.667,
\(id).ts
#EXT-X-ENDLIST
"""
        
        respond(GCDWebServerDataResponse(data: str.data(using: .utf8), contentType: "application/x-mpegURL"))
    }
    
    func sendTS() {
        respond(GCDWebServerDataResponse(data: Data(), contentType: "video/MP2T"))
    }

}

