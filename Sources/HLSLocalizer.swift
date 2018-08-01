// ===================================================================================================
// Copyright (C) 2017 Kaltura Inc.
//
// Licensed under the AGPLv3 license, unless a different license for a 
// particular library is specified in the applicable library path.
//
// You may obtain a copy of the License at
// https://www.gnu.org/licenses/agpl-3.0.html
// ===================================================================================================


import Foundation
import M3U8Kit

fileprivate let defaultAudioBitrate = 160*1024

struct MockVideoTrack: DTGVideoTrack {
    var width: Int?
    
    var height: Int?
    
    var bitrate: Int
}

public enum HLSLocalizerError: Error {
    /// sent when an unknown playlist type was encountered
    case unknownPlaylistType
    
    case malformedPlaylist

    case invalidState
}


func loadMasterPlaylist(url: URL) throws -> M3U8MasterPlaylist {
    let text = try String.init(contentsOf: url)
    
    if let playlist = M3U8MasterPlaylist(content: text, baseURL: url.deletingLastPathComponent()) {
        return playlist
    } else {
        throw HLSLocalizerError.malformedPlaylist
    }
}

func loadMediaPlaylist(url: URL, type: M3U8MediaPlaylistType) throws -> M3U8MediaPlaylist {
    let text = try String.init(contentsOf: url)

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
    
    init(streamInfo: T, mediaUrl: URL, type: M3U8MediaPlaylistType) throws {
        
        let playlist = try loadMediaPlaylist(url: mediaUrl, type: type)

        self.streamInfo = streamInfo
        self.mediaPlaylist = playlist
        self.mediaUrl = mediaUrl
        self.type = type
    }
}

typealias VideoStream = Stream<M3U8ExtXStreamInf>
typealias MediaStream = Stream<M3U8ExtXMedia>

class HLSLocalizer {
    
    enum Constants {
        static let EXT_X_KEY = "#EXT-X-KEY:"
        static let EXT_X_KEY_URI = "URI"
        static let KEYFORMAT_FAIRPLAY = "KEYFORMAT=\"com.apple.streamingkeydelivery\""
    }
    
    let itemId: String
    let masterUrl: URL
    let preferredVideoBitrate: Int?
    let downloadPath: URL
    
    var tasks = [DownloadItemTask]()
    var duration: Double = Double.nan
    var estimatedSize: Int64?
    
    var videoTrack: DTGVideoTrack?
    
    var masterPlaylist: MasterPlaylist?
    var selectedVideoStream: VideoStream?
    var selectedAudioStreams = [MediaStream]()
    var selectedTextStreams = [MediaStream]()

    init(id: String, url: URL, downloadPath: URL, preferredVideoBitrate: Int?) {
        self.itemId = id
        self.masterUrl = url
        self.preferredVideoBitrate = preferredVideoBitrate
        self.downloadPath = downloadPath
    }
    
    private func videoTrack(videoStream: M3U8ExtXStreamInf) -> DTGVideoTrack {
        return MockVideoTrack(width: Int(videoStream.resolution.width), 
                              height: Int(videoStream.resolution.height), 
                              bitrate: videoStream.bandwidth)
    }
    
    func loadMetadata() throws {
        // Load master playlist
        let master = try loadMasterPlaylist(url: masterUrl)
        
        // Only one video stream
        let videoStream = try selectVideoStream(master: master)
        
        try addAllSegments(segmentList: videoStream.mediaPlaylist.segmentList, type: M3U8MediaPlaylistTypeVideo, setDuration: true)
        
        self.videoTrack = videoTrack(videoStream: videoStream.streamInfo)
    
        aggregateTrackSize(bitrate: videoStream.streamInfo.bandwidth)
        
        self.selectedAudioStreams.removeAll()
        try addAll(streams: master.audioStreams(), type: M3U8MediaPlaylistTypeAudio)
        self.selectedTextStreams.removeAll()
        try addAll(streams: master.textStreams(), type: M3U8MediaPlaylistTypeSubtitle)
        
        // Add encryption keys download tasks for all streams
        self.addKeyDownloadTasks(from: videoStream)
        for audioStream in self.selectedAudioStreams {
            self.addKeyDownloadTasks(from: audioStream)
        }
        
        // Save the selected streams
        self.masterPlaylist = master
        self.selectedVideoStream = videoStream
    }
    

    private func reduceMasterPlaylist(_ localText: String, _ selectedBitrate: Int) -> String {
        let lines = localText.components(separatedBy: CharacterSet.newlines)
        var reducedLines = [String]()
        var removeStream = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                if line.range(of: "BANDWIDTH=\(selectedBitrate),") == nil {
                    removeStream = true
                } else {
                    reducedLines.append(line)
                }
            } else {
                if removeStream {
                    // just don't add it.
                    removeStream = false    // don't remove next line
                } else {
                    reducedLines.append(line)
                }
            }
        }
        
        return reducedLines.joined(separator: "\n")
    }
    
    private func createDirectories() throws {
        for type in DownloadItemTaskType.allTypes {
            try FileManager.default.createDirectory(at: downloadPath.appendingPathComponent(type.asString()), withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func save(text: String, as relativePath: String) throws {
        let targetFile = downloadPath.appendingPathComponent(relativePath)
        try text.write(to: targetFile, atomically: false, encoding: .utf8)
    }
    
    private func saveOriginal(text: String, url: URL, as relativePath: String) throws {
        let oText = "## Original URL: \(url.absoluteString)\n\(text)"
        try save(text: oText, as: relativePath + ".orig.txt")
    }
    
    func saveLocalFiles() throws {
        
        try createDirectories()
        
        // Localize the master
        guard let masterText = masterPlaylist?.originalText else { throw HLSLocalizerError.invalidState }
#if DEBUG
        try saveOriginal(text: masterText, url: masterUrl, as: "master.m3u8")
#endif
        let localText = NSMutableString(string: masterText)

        guard let videoStream = self.selectedVideoStream else { throw HLSLocalizerError.invalidState }
        
        localText.replace(playlistUrl: videoStream.mediaUrl, type: .video)
        
        for stream in selectedAudioStreams {
            localText.replace(playlistUrl: stream.mediaUrl, type: .audio)
        }
        
        for stream in selectedTextStreams {
            localText.replace(playlistUrl: stream.mediaUrl, type: .text)
        }
        
        let selectedVideoBitrate = videoStream.streamInfo.bandwidth
        
        let reducedMasterPlaylist = reduceMasterPlaylist(localText as String, selectedVideoBitrate)

        try save(text: reducedMasterPlaylist, as: "master.m3u8")        

        // Localize the selected video stream
        try saveMediaPlaylist(videoStream.mediaPlaylist, originalUrl: videoStream.mediaUrl, type: .video)
        
        // Localize the selected audio and text streams
        for stream in selectedAudioStreams {
            try saveMediaPlaylist(stream.mediaPlaylist, originalUrl: stream.mediaUrl, type: .audio)
        }

        for stream in selectedTextStreams {
            try saveMediaPlaylist(stream.mediaPlaylist, originalUrl: stream.mediaUrl, type: .text)
        }
}
    
    private func _saveMediaPlaylist(_ mediaPlaylist: MediaPlaylist, originalUrl: URL, type: DownloadItemTaskType) throws {
        
        guard let originalText = mediaPlaylist.originalText else { throw HLSLocalizerError.invalidState }
        #if DEBUG
            try saveOriginal(text: originalText, url: originalUrl, as: originalUrl.mediaPlaylistRelativeLocalPath(as: type))
        #endif

        let localText = NSMutableString(string: originalText)
        
        guard let segments = mediaPlaylist.segmentList else {throw HLSLocalizerError.invalidState}
        for i in 0 ..< segments.countInt {
            try localText.replace(segmentUrl: segments[i].uri.absoluteString, relativeTo: originalUrl.deletingLastPathComponent())
        }
        
        let target = originalUrl.mediaPlaylistRelativeLocalPath(as: type)
        try save(text: localText as String, as: target)
    }
    
    private func isHLSAESKey(line: String) -> Bool {
        return line.hasPrefix(Constants.EXT_X_KEY) && !line.contains(Constants.KEYFORMAT_FAIRPLAY)
    }
    
    private func saveMediaPlaylist(_ mediaPlaylist: MediaPlaylist, originalUrl: URL, type: DownloadItemTaskType) throws {
        guard let originalText = mediaPlaylist.originalText else { throw HLSLocalizerError.invalidState }
        #if DEBUG
            try saveOriginal(text: originalText, url: originalUrl, as: originalUrl.mediaPlaylistRelativeLocalPath(as: type))
        #endif

        guard let segments = mediaPlaylist.segmentList else { throw HLSLocalizerError.invalidState }
        var localLines = [String]()
        var i = 0
        for line in originalText.components(separatedBy: CharacterSet.newlines) {
            if line.isEmpty {
                continue
            }
            if !line.hasPrefix("#") && i < segments.countInt && line == segments[i].uri.absoluteString {
                localLines.append(segments[i].mediaURL().segmentRelativeLocalPath())
                i += 1
            } else if isHLSAESKey(line: line) { 
                // has AES-128 key replace uri with local path
                let keyAttributes = getSegmentAttributes(fromSegment: line, segmentPrefix: Constants.EXT_X_KEY, seperatedBy: ",")
                var updatedLine = Constants.EXT_X_KEY
                for (index, attribute) in keyAttributes.enumerated() {
                    var updatedAttribute = attribute
                    if attribute.hasPrefix(Constants.EXT_X_KEY_URI) {
                        var mutableAttribute = attribute
                        // remove the url attribute tag
                        mutableAttribute = mutableAttribute.replacingOccurrences(of: Constants.EXT_X_KEY_URI + "=", with: "")
                        // remove quotation marks
                        let uri = mutableAttribute.replacingOccurrences(of: "\"", with: "")
                        // create the content url
                        let mediaUrl: URL = segments[i].mediaURL()
                        guard let url = createContentUrl(from: uri, originalContentUrl: mediaUrl) else { break }
                        updatedAttribute = "\(Constants.EXT_X_KEY_URI)=\"../key/\(url.segmentRelativeLocalPath())\""
                    }
                    if index != keyAttributes.count - 1 {
                        updatedLine.append("\(updatedAttribute),")
                    } else {
                        updatedLine.append(updatedAttribute)
                    }
                }
                localLines.append(updatedLine)
            } else {
                localLines.append(line)
            }
        }
        
        let target = originalUrl.mediaPlaylistRelativeLocalPath(as: type)
        try save(text: localLines.joined(separator: "\n") as String, as: target)
    }
    
    private func selectVideoStream(master: MasterPlaylist) throws -> VideoStream {
        let streams = master.videoStreams()
        
        // Algorithm: sort ascending. Then find the first stream with bandwidth >= preferredVideoBitrate.
        
        streams.sortByBandwidth(inOrder: .orderedAscending)
        
        var selectedStreamInfo: M3U8ExtXStreamInf?
        if let bitrate = preferredVideoBitrate {
            for i in 0 ..< streams.countInt {
                if streams[i].bandwidth >= bitrate {
                    selectedStreamInfo = streams[i]
                    break
                }
            }
        }
        
        if selectedStreamInfo == nil {
            selectedStreamInfo = streams.lastXStreamInf() // highest bitrate
        }
        
        guard let streamInfo = selectedStreamInfo else {throw NSError()}
        
        return try VideoStream(streamInfo: streamInfo, mediaUrl: streamInfo.m3u8URL(), type: M3U8MediaPlaylistTypeVideo)
    }
    
    private func addAllSegments(segmentList: M3U8SegmentInfoList, type: M3U8MediaPlaylistType, setDuration: Bool = false) throws {
                    
        var downloadItemTasks = [DownloadItemTask]()
        var duration = 0.0
        var order = 0
        for i in 0 ..< segmentList.countInt {
            duration += segmentList[i].duration
            
            guard let trackType = type.asDownloadItemTaskType() else {
                throw HLSLocalizerError.unknownPlaylistType
            }
            order += 1
            downloadItemTasks.append(downloadItemTask(url: segmentList[i].mediaURL(), type: trackType, order: order))
        }
        
        if setDuration {
            self.duration = duration
        }
        
        self.tasks.append(contentsOf: downloadItemTasks)
    }
    
    private func downloadItemTask(url: URL, type: DownloadItemTaskType, order: Int) -> DownloadItemTask {
        let destinationUrl = downloadPath.appendingPathComponent(type.asString(), isDirectory: true)
            .appendingPathComponent(url.absoluteString.md5())
            .appendingPathExtension(url.pathExtension)
        return DownloadItemTask(dtgItemId: self.itemId, contentUrl: url, type: type, destinationUrl: destinationUrl, order: order)
    }
    
    /// Adds download tasks for all encrpytion keys from the provided playlist.
    private func addKeyDownloadTasks<T>(from stream: Stream<T>) {
        let keySegmentTagPrefix = Constants.EXT_X_KEY
        let uriAttributePrefix = Constants.EXT_X_KEY_URI + "="
        let lines = stream.mediaPlaylist.originalText.components(separatedBy: .newlines)
        
        var downloadItemTasks = [DownloadItemTask]()
        
        var order = 0
        for line in lines {
            if isHLSAESKey(line: line) {
                order += 1
                // the attributes of the key are seperated by commas, need to seperate and get the URI to create the download task.
                let keyAttributes = self.getSegmentAttributes(fromSegment: line, segmentPrefix: keySegmentTagPrefix, seperatedBy: ",")
                for attribute in keyAttributes {
                    if attribute.hasPrefix(uriAttributePrefix) { // extract the uri
                        var mutableAttribute = attribute
                        // can force unwrap because we check the prefix on the start.
                        let urlAttributeRange = mutableAttribute.range(of: uriAttributePrefix)!
                        // remove the url attribute tag
                        mutableAttribute = mutableAttribute.replacingCharacters(in: urlAttributeRange, with: "")
                        // remove quotation marks
                        let uri = mutableAttribute.replacingOccurrences(of: "\"", with: "")
                        // create the content url
                        guard let url = createContentUrl(from: uri, originalContentUrl: stream.mediaUrl) else { break }
                        // create and add download task
                        let downloadTask = downloadItemTask(url: url, type: .key, order: order)
                        downloadItemTasks.append(downloadTask)
                    }
                }
            }
        }
        
        self.tasks.append(contentsOf: downloadItemTasks)
    }
    
    /// gets a segment attributes.
    private func getSegmentAttributes(fromSegment segment: String, segmentPrefix: String, seperatedBy seperator: String) -> [String] {
        // a mutable copy of the line so we can extract data from it.
        var mutableSegment = segment
        // can force unwrap because we check the prefix on the start.
        guard let segmentTagRange = mutableSegment.range(of: segmentPrefix) else { return [] }
        mutableSegment = mutableSegment.replacingCharacters(in: segmentTagRange, with: "")
        // seperate the attributes by the seperator
        return mutableSegment.components(separatedBy: seperator)
    }
    
    private func createContentUrl(from uri: String, originalContentUrl: URL) -> URL? {
        let url: URL
        if uri.hasPrefix("http") {
            guard let httpUrl = URL(string: uri) else { return nil }
            url = httpUrl
        } else {
            url = originalContentUrl.deletingLastPathComponent().appendingPathComponent(uri, isDirectory: false)
        }
        return url
    }
    
    private func addAll(streams: M3U8ExtXMediaList?, type: M3U8MediaPlaylistType) throws {
        guard let streams = streams else { return }
        
        for i in 0 ..< streams.countInt {
            
            let url: URL! = streams[i].m3u8URL()
            do {
                let stream = try MediaStream(streamInfo: streams[i], mediaUrl: url, type: type)
                try addAllSegments(segmentList: stream.mediaPlaylist.segmentList, type: type)
                
                switch type {
                case M3U8MediaPlaylistTypeAudio:
                    let bitrate = streams[i].bandwidth()
                    aggregateTrackSize(bitrate: bitrate > 0 ? bitrate : defaultAudioBitrate)
                    selectedAudioStreams.append(stream)
                case M3U8MediaPlaylistTypeSubtitle:
                    selectedTextStreams.append(stream)
                default:
                    throw HLSLocalizerError.unknownPlaylistType
                }
            } catch {
                log.warning("Skipping malformed playlist")
            }
        }
    }
    
    private func aggregateTrackSize(bitrate: Int) {
        let estimatedTrackSize = Int64(Double(bitrate) * duration / 8)
        estimatedSize = (estimatedSize ?? 0) + estimatedTrackSize
    }
}

extension HLSLocalizer {
    
    var availableTextTracksInfo: [TrackInfo] {
        guard let masterPlaylist = self.masterPlaylist else { return [] }
        return self.getTracksInfo(from: masterPlaylist.textStreams(), type: .text)
    }
    
    var availableAudioTracksInfo: [TrackInfo] {
        guard let masterPlaylist = self.masterPlaylist, let audioStreams = masterPlaylist.audioStreams() else { return [] }
        return self.getTracksInfo(from: audioStreams, type: .audio)
    }
    
    var selectedTextTracksInfo: [TrackInfo] {
        guard self.selectedTextStreams.count > 0 else { return [] }
        let streamsInfo = self.selectedTextStreams.map { $0.streamInfo }
        return self.getTracksInfo(from: streamsInfo, type: .text)
    }
    
    var selectedAudioTracksInfo: [TrackInfo] {
        guard self.selectedAudioStreams.count > 0 else { return [] }
        let streamsInfo = self.selectedAudioStreams.map { $0.streamInfo }
        return self.getTracksInfo(from: streamsInfo, type: .audio)
    }
    
    private func getTracksInfo(from streamList: M3U8ExtXMediaList, type: TrackInfo.TrackType) -> [TrackInfo] {
        var tracksInfo: [TrackInfo] = []
        for i in 0..<streamList.countInt {
            let stream = streamList[i]
            tracksInfo.append(TrackInfo(languageCode: stream.language(), title: stream.name(), type: type))
        }
        return tracksInfo
    }
    
    private func getTracksInfo(from streams: [M3U8ExtXMedia], type: TrackInfo.TrackType) -> [TrackInfo] {
        var tracksInfo: [TrackInfo] = []
        for stream in streams {
            tracksInfo.append(TrackInfo(languageCode: stream.language(), title: stream.name(), type: type))
        }
        return tracksInfo
    }
}

/************************************************************/
// MARK: - M3U8Kit convenience extensions
/************************************************************/

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
