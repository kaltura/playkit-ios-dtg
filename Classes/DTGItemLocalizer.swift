
import Foundation
import M3U8Kit


public struct MediaSegment {
    let sourceUrl: URL
    let targetPath: String
}

public class DTGItemLocalizer {
    
    let itemId: String
    let masterUrl: URL
    let preferredVideoBitrate: Int
    let downloadPath: String
    
    public var tasks = [MediaSegment]()
    public var duration: Double = Double.nan
    
    public init(id: String, url: URL, preferredVideoBitrate: Int, baseDownloadPath: String) {
        self.itemId = id
        self.masterUrl = url
        self.preferredVideoBitrate = preferredVideoBitrate
        self.downloadPath = "\(baseDownloadPath)/items/\(self.itemId)"
    }
    
    public func loadMetadata(callback: (Error?) -> Void) {
        // Load master playlist
        do {
            let master = try MasterPlaylist(contentOf: masterUrl)
            
            // Only one video stream
            let videoStream = selectVideoStream(master: master)
        
            try addAllSegments(mediaUrl: videoStream.m3u8URL(), type: M3U8MediaPlaylistTypeVideo, setDuration: true)
            
            try addAll(streams: master.audioStreams(), type: M3U8MediaPlaylistTypeAudio)
            try addAll(streams: master.textStreams(), type: M3U8MediaPlaylistTypeSubtitle)
        } catch {
            callback(error)
        }

        // Success
        callback(nil)
    }
    
    func selectVideoStream(master: MasterPlaylist) -> M3U8ExtXStreamInf {
        let streams = master.videoStreams()
        
        // Algorithm: sort ascending. Then find the first stream with bandwidth >= preferredVideoBitrate.
        
        streams.sortByBandwidth(inOrder: .orderedAscending)
        
        for i in 0 ..< streams.countInt {
            if streams[i].bandwidth >= preferredVideoBitrate {
                return streams[i]
            }
        }
        
        // Not found -- this means the client asked for a bitrate higher than available. Return the last.
        return streams.lastXStreamInf()
    }
    
    func addAllSegments(mediaUrl: URL, type: M3U8MediaPlaylistType, setDuration: Bool = false) throws {
        let playlist = try MediaPlaylist(contentOf: mediaUrl, type: type)
        
        guard let segmentList = playlist.segmentList else {return}
        
        var segments = [MediaSegment]()
        var duration = 0.0
        for i in 0 ..< segmentList.countInt {
            duration += segmentList[i].duration
            
            segments.append(mediaSegment(url: segmentList[i].mediaURL(), type: type))
        }
        
        if setDuration {
            self.duration = duration
        } else if duration != self.duration {
            print("Warning: unmatched duration, \(duration) != \(self.duration)")
        }
        
        self.tasks.append(contentsOf: segments)
    }
    
    func mediaSegment(url: URL, type: M3U8MediaPlaylistType) -> MediaSegment {
        let targetPath = "\(downloadPath)/\(type.asString())/\(url.absoluteString.md5()).\(url.pathExtension))"
        return MediaSegment(sourceUrl: url, targetPath: targetPath)
    }
    
    func addAll(streams: M3U8ExtXMediaList?, type: M3U8MediaPlaylistType) throws {
        guard let streams = streams else { return }
        
        for i in 0 ..< streams.countInt {
            try addAllSegments(mediaUrl: streams[i].m3u8URL(), type: type)
        }
    }
}

typealias MasterPlaylist = M3U8MasterPlaylist
typealias MediaPlaylist = M3U8MediaPlaylist

extension M3U8MediaPlaylistType {
    func asString() -> String {
        switch self {
        case M3U8MediaPlaylistTypeVideo:
            return "video"
        case M3U8MediaPlaylistTypeAudio:
            return "audio"
        case M3U8MediaPlaylistTypeSubtitle:
            return "text"
        default:
            return "unknown"
        }
    }
}

extension MasterPlaylist {
    func videoStreams() -> M3U8ExtXStreamInfList {
        return self.xStreamList
    }
    
    func audioStreams() -> M3U8ExtXMediaList? {
        return self.xMediaList.audio()
    }
    
    func textStreams() -> M3U8ExtXMediaList {
        return self.xMediaList.subtitle()
    }
}

extension M3U8ExtXStreamInfList {
    subscript(index: Int) -> M3U8ExtXStreamInf {
        get {
            return self.xStreamInf(at: UInt(index))
        }
    }
    var countInt: Int {
        return Int(count)
    }
}

extension M3U8ExtXMediaList {
    subscript(index: Int) -> M3U8ExtXMedia {
        get {
            return self.xMedia(at: UInt(index))
        }
    }
    var countInt: Int {
        return Int(count)
    }
}

extension M3U8SegmentInfoList {
    subscript(index: Int) -> M3U8SegmentInfo {
        get {
            return self.segmentInfo(at: UInt(index))
        }
    }
    var countInt: Int {
        return Int(count)
    }
}

extension String {
    func md5() -> String {
        return CCBridge.md5(with: self)
    }
}
