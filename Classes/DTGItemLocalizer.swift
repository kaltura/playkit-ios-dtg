
import Foundation
import M3U8Kit

struct MockVideoTrack: DTGVideoTrack {
    var width: Int?
    
    var height: Int?
    
    var bitrate: Int
    
    var codecs: [String]?
}

enum DTGItemLocalizerError: Error {
    /// sent when an unknown playlist type was encountered
    case unknownPlaylistType
}

class DTGItemLocalizer {
    
    let itemId: String
    let masterUrl: URL
    let preferredVideoBitrate: Int?
    let downloadPath: URL
    
    var tasks = [DownloadItemTask]()
    var duration: Double = Double.nan
    var estimatedSize: Int64?
    
    var videoTrack: DTGVideoTrack?
    
    init(id: String, url: URL, preferredVideoBitrate: Int?, storagePath: URL) {
        self.itemId = id
        self.masterUrl = url
        self.preferredVideoBitrate = preferredVideoBitrate
        let subPath = "items/\(id.safeItemPathName())"
        self.downloadPath = storagePath.appendingPathComponent(subPath, isDirectory: true)
    }
    
    func videoTrack(videoStream: M3U8ExtXStreamInf) -> DTGVideoTrack {
        return MockVideoTrack(width: Int(videoStream.resolution.width), 
                              height: Int(videoStream.resolution.height), 
                              bitrate: videoStream.bandwidth, 
                              codecs: videoStream.codecs as? [String])
    }
    
    func loadMetadata(callback: (Error?) -> Void) {
        // Load master playlist
        do {
            let master = try MasterPlaylist(contentOf: masterUrl)
            
            // Only one video stream
            let videoStream = selectVideoStream(master: master)
            
            self.videoTrack = videoTrack(videoStream: videoStream)
        
            try addAllSegments(mediaUrl: videoStream.m3u8URL(), type: M3U8MediaPlaylistTypeVideo, setDuration: true)
            aggregateTrackSize(bitrate: videoStream.bandwidth)
            
            try addAll(streams: master.audioStreams(), type: M3U8MediaPlaylistTypeAudio)
            try addAll(streams: master.textStreams(), type: M3U8MediaPlaylistTypeSubtitle)

            // Success
            callback(nil)
            
        } catch {
            callback(error)
        }
    }
    
    private func selectVideoStream(master: MasterPlaylist) -> M3U8ExtXStreamInf {
        let streams = master.videoStreams()
        
        // Algorithm: sort ascending. Then find the first stream with bandwidth >= preferredVideoBitrate.
        
        streams.sortByBandwidth(inOrder: .orderedAscending)
        
        if let bitrate = preferredVideoBitrate {
            for i in 0 ..< streams.countInt {
                if streams[i].bandwidth >= bitrate {
                    return streams[i]
                }
            }
        }

        // Default to using the highest available bitrate.
        return streams.lastXStreamInf()
    }
    
    private func addAllSegments(mediaUrl: URL, type: M3U8MediaPlaylistType, setDuration: Bool = false) throws {
        let playlist = try MediaPlaylist(contentOf: mediaUrl, type: type)
        
        guard let segmentList = playlist.segmentList else { return }
        
        var downloadItemTasks = [DownloadItemTask]()
        var duration = 0.0
        for i in 0 ..< segmentList.countInt {
            duration += segmentList[i].duration
            
            try downloadItemTasks.append(downloadItemTask(url: segmentList[i].mediaURL(), type: type))
        }
        
        if setDuration {
            self.duration = duration
        }
        
        self.tasks.append(contentsOf: downloadItemTasks)
    }
    
    private func downloadItemTask(url: URL, type: M3U8MediaPlaylistType) throws -> DownloadItemTask {
        guard let trackType = type.asDTGTrackType() else {
            throw DTGItemLocalizerError.unknownPlaylistType
        }
        let destinationUrl = downloadPath.appendingPathComponent(type.asString(), isDirectory: true)
            .appendingPathComponent(url.absoluteString.md5())
            .appendingPathExtension(url.pathExtension)
        return DownloadItemTask(contentUrl: url, trackType: trackType, destinationUrl: destinationUrl, resumeData: nil)
    }
    
    private func addAll(streams: M3U8ExtXMediaList?, type: M3U8MediaPlaylistType) throws {
        guard let streams = streams else { return }
        
        for i in 0 ..< streams.countInt {
            try addAllSegments(mediaUrl: streams[i].m3u8URL(), type: type)
            aggregateTrackSize(bitrate: streams[i].bandwidth())
        }
    }
    
    private func aggregateTrackSize(bitrate: Int) {
        let estimatedTrackSize = Int64(Double(bitrate) * duration / 8)
        estimatedSize = (estimatedSize ?? 0) + estimatedTrackSize
    }
}

// M3U8Kit convenience extensions

typealias MasterPlaylist = M3U8MasterPlaylist
typealias MediaPlaylist = M3U8MediaPlaylist

private extension M3U8MediaPlaylistType {
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
    
    func asDTGTrackType() -> DTGTrackType? {
        switch self {
        case M3U8MediaPlaylistTypeVideo:
            return .video
        case M3U8MediaPlaylistTypeAudio:
            return .audio
        case M3U8MediaPlaylistTypeSubtitle:
            return .text
        default:
            return nil
        }
    }
}

private extension M3U8MasterPlaylist {
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

private extension M3U8ExtXStreamInfList {
    subscript(index: Int) -> M3U8ExtXStreamInf {
        get {
            return self.xStreamInf(at: UInt(index))
        }
    }
    var countInt: Int {
        return Int(count)
    }
}

private extension M3U8ExtXMediaList {
    subscript(index: Int) -> M3U8ExtXMedia {
        get {
            return self.xMedia(at: UInt(index))
        }
    }
    var countInt: Int {
        return Int(count)
    }
}

private extension M3U8SegmentInfoList {
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
    
    func safeItemPathName() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed) ?? self.md5()
    }
}
