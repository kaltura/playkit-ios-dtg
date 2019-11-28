//
//  HLSLocalizerUtils.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 21/06/2019.
//

import Foundation
import M3U8Kit
import PlayKitUtils

public enum HLSLocalizerError: Error {
    /// sent when an unknown playlist type was encountered
    case unknownPlaylistType
    
    case malformedPlaylist
    
    case invalidState
}


fileprivate let YES = "YES"
fileprivate let NO = "NO"

typealias CodecTag = String
typealias TrackCodec = DTGSelectionOptions.TrackCodec
typealias M3U8Stream = M3U8ExtXStreamInf

// This function works like String.init(contentsOf:url), but it allows to customize the user-agent header
func syncHttpGetUtf8String(url: URL) throws -> String {
    
    var request = URLRequest(url: url)
    request.addValue(ContentManager.userAgent, forHTTPHeaderField: "user-agent")
    
    var data: Data?
    var error: Error?
    
    // We need to block the calling thread (which should NOT be the main thread anyway).
    let sem = DispatchSemaphore(value: 0)
    
    URLSession.shared.dataTask(with: request) { (d, resp, e) in
        
        data = d
        error = e
        
        sem.signal()
        
        }.resume()
    
    if sem.wait(timeout: DispatchTime.now() + 10) == .timedOut {
        throw DTGError.networkTimeout(url: url.absoluteString)
    }
    
    
    if let data = data {
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    if let err = error {
        throw err
    }
    
    // we should never get here -- there must be either error or data, but just in case return empty String
    return ""
}

struct VideoTrack: DTGVideoTrack {
    let width: Int?
    
    let height: Int?
    
    let bitrate: Int
    
    let audioGroup: String?
    
    let textGroup: String?
    
    func groupId(for type: M3U8MediaPlaylistType) -> String? {
        switch type {
        case M3U8MediaPlaylistTypeAudio: return self.audioGroup
        case M3U8MediaPlaylistTypeSubtitle: return self.textGroup
        default: return nil
        }
    }
}



func loadMasterPlaylist(url: URL) throws -> M3U8MasterPlaylist {
    let text = try syncHttpGetUtf8String(url: url)
    
    if let playlist = M3U8MasterPlaylist(content: text, baseURL: url.deletingLastPathComponent()) {
        return playlist
    } else {
        throw HLSLocalizerError.malformedPlaylist
    }
}

func loadMediaPlaylist(url: URL, type: M3U8MediaPlaylistType) throws -> M3U8MediaPlaylist {
    let text = try syncHttpGetUtf8String(url: url)
    
    if let playlist = M3U8MediaPlaylist(content: text, type: type, baseURL: url.deletingLastPathComponent()) {
        return playlist
    } else {
        throw HLSLocalizerError.malformedPlaylist
    }
}

class Stream<T> {
    let streamInfo: T
    let mediaUrl: URL
    let mediaPlaylist: M3U8MediaPlaylist
    let type: M3U8MediaPlaylistType
    let mapUrl: URL?
    
    init(streamInfo: T, mediaUrl: URL, type: M3U8MediaPlaylistType) throws {
        
        let playlist = try loadMediaPlaylist(url: mediaUrl, type: type)
        
        self.streamInfo = streamInfo
        self.mediaPlaylist = playlist
        self.mediaUrl = mediaUrl
        self.type = type
        
        if type != M3U8MediaPlaylistTypeSubtitle {
            self.mapUrl = Stream.findMap(text: playlist.originalText)
        } else {
            self.mapUrl = nil
        }
    }
    
    static func findMap(text: String) -> URL? {
        let reader = M3U8LineReader(text: text)
        while true {
            guard let line = reader?.next() else {return nil}
            guard line.starts(with: M3U8_EXT_X_MAP) else {continue}
            
            guard let attr = line.m3u8Attribs(prefix: M3U8_EXT_X_MAP) else {continue}
            
            if let uri = attr[M3U8_EXT_X_MAP_URI] {
                return URL(string: uri)
            } else {
                return nil
            }
        }
    }
    
    var trackType: DownloadItemTaskType {
        switch type {
        case M3U8MediaPlaylistTypeAudio:
            return .audio
        case M3U8MediaPlaylistTypeVideo: 
            fallthrough
        case M3U8MediaPlaylistTypeMedia:
            return .video
        case M3U8MediaPlaylistTypeSubtitle:
            return .text
        default:
            return .video
        }
    }
}

fileprivate func qs(_ s: String) -> String {
    return "\"\(s)\""
}

class VideoStream: Stream<M3U8ExtXStreamInf>, CustomStringConvertible {
    
    var description: String {
        return localMasterLine(hasAudio: true, hasText: true).replacingOccurrences(of: "\n", with: "\t")
    }
    
    func localMasterLine(hasAudio: Bool, hasText: Bool) -> String {
        let stream = streamInfo;
        
        var attribs = [(String, String)]()
        
        attribs.append((M3U8_EXT_X_STREAM_INF_BANDWIDTH, String(stream.bandwidth)))
        
        attribs.append((M3U8_EXT_X_STREAM_INF_RESOLUTION, "\(Int(stream.resolution.width))x\(Int(stream.resolution.height))"))
        
        if let audio = stream.audio, audio.count > 0, hasAudio {
            attribs.append((M3U8_EXT_X_STREAM_INF_AUDIO, qs(audio)))
        }
        
        if let subtitles = stream.subtitles, subtitles.count > 0, hasText {
            attribs.append((M3U8_EXT_X_STREAM_INF_SUBTITLES, qs(subtitles)))
        }
        
        if let codecsArray = stream.codecs as NSArray?, codecsArray.count > 0 {
            let codecs = codecsArray.componentsJoined(by: ",")
            attribs.append((M3U8_EXT_X_STREAM_INF_CODECS, qs(codecs)))
        }
        
        return M3U8_EXT_X_STREAM_INF +
            attribs.map { $0 + "=" + $1 }.joined(separator: ",") +
            "\n" +
            self.mediaUrl.mediaPlaylistRelativeLocalPath(as: .video)
    }
}

class MediaStream: Stream<M3U8ExtXMedia>, CustomStringConvertible {
    
    var description: String {
        return localMasterLine().replacingOccurrences(of: "\n", with: "\t")
    }
    
    func localMasterLine() -> String {
        
        let stream = streamInfo;
        
        var attribs = [(String, String)]()
        
        attribs.append((M3U8_EXT_X_MEDIA_TYPE, stream.type()))
        attribs.append((M3U8_EXT_X_MEDIA_AUTOSELECT, stream.autoSelect() ? YES : NO))
        attribs.append((M3U8_EXT_X_MEDIA_DEFAULT, stream.isDefault() ? YES : NO))
        
        if let lang = stream.language() {
            attribs.append((M3U8_EXT_X_MEDIA_LANGUAGE, qs(lang)))
        }
        
        if let groupId = stream.groupId() {
            attribs.append((M3U8_EXT_X_MEDIA_GROUP_ID, qs(groupId)))
        }
        
        if let name = stream.name() {
            attribs.append((M3U8_EXT_X_MEDIA_NAME, qs(name)))
        }
        
        attribs.append((M3U8_EXT_X_MEDIA_FORCED, stream.forced() ? YES : NO))
        
        if stream.bandwidth() > 0 {
            attribs.append((M3U8_EXT_X_MEDIA_BANDWIDTH, String(stream.bandwidth())))
        }
        
        attribs.append((M3U8_EXT_X_MEDIA_URI, qs(self.mediaUrl.mediaPlaylistRelativeLocalPath(as: self.trackType))))
        
        return M3U8_EXT_X_MEDIA + attribs.map { $0 + "=" + $1 }.joined(separator: ",")
    }
    
}

extension String {
    func md5() -> String {
        return md5WithString(self)
    }
    
    func safeItemPathName() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed) ?? self.md5()
    }
    
    func m3u8Attribs(prefix: String) -> [String:String]? {
        return parseM3U8Attributes(self, prefix)
    }

    func replacing(playlistUrl: URL?, type: DownloadItemTaskType) -> String {
        if let url = playlistUrl {
            return self.replacingOccurrences(of: url.absoluteString, with: url.mediaPlaylistRelativeLocalPath(as: type))
        } else {
            return self
        }
    }
}

extension URL {
    func mediaPlaylistRelativeLocalPath(as type: DownloadItemTaskType) -> String {
        return "\(type.asString())/\(absoluteString.md5()).\(pathExtension)"
    }
    
    func segmentRelativeLocalPath() -> String {
        return "\(absoluteString.md5()).\(pathExtension)"
    }
}

extension NSMutableString {
    func replace(playlistUrl: URL?, type: DownloadItemTaskType) {
        if let url = playlistUrl {
            self.replaceOccurrences(of: url.absoluteString, with: url.mediaPlaylistRelativeLocalPath(as: type), options: [], range: NSMakeRange(0, self.length))
        }
    }
    
    func replace(segmentUrl: String, relativeTo: URL) throws {
        guard let relativeLocalPath = URL(string: segmentUrl, relativeTo: relativeTo)?.segmentRelativeLocalPath() else { throw HLSLocalizerError.invalidState }
        self.replaceOccurrences(of: segmentUrl, with: relativeLocalPath, options: [], range: NSMakeRange(0, self.length))
    }
}

extension DTGSelectionOptions: CustomStringConvertible {
    public var description: String {
        return """
        Video: height=\(videoHeight ?? -1) width=\(videoWidth ?? -1) codecs=\(videoCodecs ?? []) bitrates=\(videoBitrates)
        Audio: all=\(allAudioLanguages) list=\(audioLanguages ?? []) codecs=\(audioCodecs ?? [])
        Text: all=\(allTextLanguages) list=\(textLanguages ?? [])
        """
    }
    
    func fullVideoCodecPriority() -> [CodecTag] {
        return DTGSelectionOptions.fullCodecPriority(requestedTags: (videoCodecs ?? []).map {$0.tag}, allowedTags: allowedVideoCodecTags)
    }
    
    func fullAudioCodecPriority() -> [CodecTag] {
        return DTGSelectionOptions.fullCodecPriority(requestedTags: (audioCodecs ?? []).map {$0.tag}, allowedTags: allowedAudioCodecTags)
    }
    
    static func fullCodecPriority(requestedTags: [CodecTag], allowedTags: [CodecTag]) -> [CodecTag] {
        var codecPriority = requestedTags
        for codec in allowedTags {
            if !codecPriority.contains(codec) {
                codecPriority.append(codec)
            }
        }
        return codecPriority
    }
}

extension TrackCodec: CustomStringConvertible {
    public var description: String {
        return tag
    }
    
    static let audioCodecs: [TrackCodec] = {
        return defaultAudioCodecOrder
    }()
    
    static let videoCodecs: [TrackCodec] = {
        return defaultVideoCodecOrder
    }()
    
    static let defaultVideoCodecOrder: [TrackCodec] = [.hevc, .avc1]
    
    static let defaultAudioCodecOrder: [TrackCodec] = [.eac3, .ac3, .mp4a]
    
    var tag: CodecTag {
        switch self {
        case .avc1: return "avc1"
        case .hevc: return "hvc1"
        case .mp4a: return "mp4a"
        case .ac3: return "ac-3"
        case .eac3: return "ec-3"
        }
    }
    
    
    func isAllowed(with options: DTGSelectionOptions) -> Bool {
        switch self {
        case .avc1: return true
        case .hevc: return CodecSupport.hardwareHEVC || CodecSupport.softwareHEVC && options.allowInefficientCodecs
        case .mp4a: return true
        case .ac3: return CodecSupport.ac3
        case .eac3: return CodecSupport.ec3
        }
    }
}

// Util
func filter(streams: [M3U8Stream], 
                        sortOrder: (M3U8Stream, M3U8Stream) -> Bool?, 
                        filter: (M3U8Stream) -> Bool) -> [M3U8Stream] {
    
    
    if streams.count < 2 {
        return streams
    }
    
    let sorted = streams.stableSorted(by: sortOrder)
    
    let filtered = sorted.filter( filter )
    
    if filtered.isEmpty {
        if let s = sorted.last {
            return [s]
        }
    }
    return filtered
}
