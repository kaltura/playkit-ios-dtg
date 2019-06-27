//
//  M3U8Kit+Utils.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 21/06/2019.
//

import Foundation
import M3U8Kit

typealias MasterPlaylist = M3U8MasterPlaylist
typealias MediaPlaylist = M3U8MediaPlaylist

extension M3U8Stream {
    func codecTags() -> Set<CodecTag> {
        // `codecs` is an array of String, but it's declared as a non-generic `Array`.
        // It might also be nil.
        guard let codecs = self.codecs as? [String] else { return Set() }
        
        var tags = [CodecTag]()
        
        for c in codecs { 
            guard let tag = c.split(separator: ".").first else {continue}
            tags.append(CodecTag(tag))
        }
        
        return Set(tags)
    }
    
    func usesUnsupportedCodecs(with options: DTGSelectionOptions) -> Bool {
        for tag in codecTags() {
            if !options.allowedCodecTags.contains(tag) {
                return true
            }
        }
        return false
    }
    
    func videoCodec() -> CodecTag? {
        for tag in codecTags() {
            if TrackCodec.videoCodecs.contains(where: { $0.tag == tag }) {
                return tag
            }
        }
        return nil
    }
    
    func audioCodec() -> CodecTag? {
        for tag in codecTags() {
            if TrackCodec.audioCodecs.contains(where: { $0.tag == tag }) {
                return tag
            }
        }
        return nil
    }
}

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
    
    func asDownloadItemTaskType() -> DownloadItemTaskType? {
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
    
    func isAudio() -> Bool {
        return self == M3U8MediaPlaylistTypeAudio
    }
    
    func isText() -> Bool {
        return self == M3U8MediaPlaylistTypeSubtitle
    }
}

extension M3U8MasterPlaylist {
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

