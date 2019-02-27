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


struct MockVideoTrack: DTGVideoTrack {
    let width: Int?
    
    let height: Int?
    
    let bitrate: Int
    
    let audioGroup: String?
    
    let textGroup: String?
}

extension MockVideoTrack {
    func groupId(for type: M3U8MediaPlaylistType) -> String? {
        switch type {
        case M3U8MediaPlaylistTypeAudio: return self.audioGroup
        case M3U8MediaPlaylistTypeSubtitle: return self.textGroup
        default: return nil
        }
    }
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

class Stream<T>: CustomStringConvertible {
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
        
        self.mapUrl = Stream.findMap(text: playlist.originalText)
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
    
    var description: String {
        return String(describing: streamInfo)
    }
}

typealias VideoStream = Stream<M3U8ExtXStreamInf>
typealias MediaStream = Stream<M3U8ExtXMedia>

fileprivate let KEYFORMAT_FAIRPLAY =    "KEYFORMAT=\"com.apple.streamingkeydelivery\""
fileprivate let MASTER_PLAYLIST_NAME =  "master.m3u8"

class HLSLocalizer {
    
    
    let itemId: String
    let masterUrl: URL
    let downloadPath: URL
    let options: DTGSelectionOptions
    
    var tasks = [DownloadItemTask]()
    var duration: Double = Double.nan
    var estimatedSize: Int64?
    
    var videoTrack: MockVideoTrack?
    
    var masterPlaylist: MasterPlaylist?
    var selectedVideoStream: VideoStream?
    var selectedAudioStreams = [MediaStream]()
    var selectedTextStreams = [MediaStream]()
    
    let audioBitrateEstimation: Int

    init(id: String, url: URL, downloadPath: URL, options: DTGSelectionOptions?, audioBitrateEstimation: Int) {
        self.itemId = id
        self.masterUrl = url
        self.options = options ?? DTGSelectionOptions()
        self.downloadPath = downloadPath
        self.audioBitrateEstimation = audioBitrateEstimation
    }
    
    private func videoTrack(videoStream: M3U8ExtXStreamInf) -> MockVideoTrack {
        return MockVideoTrack(width: Int(videoStream.resolution.width), 
                              height: Int(videoStream.resolution.height), 
                              bitrate: videoStream.bandwidth, 
                              audioGroup: videoStream.audio, 
                              textGroup: videoStream.subtitles)
    }
    
    func loadMetadata() throws {
        // Load master playlist
        let master = try loadMasterPlaylist(url: masterUrl)
        
        // Only one video stream
        let videoStream = try selectVideoStream(master: master)
        
        
        if let mapUrl = videoStream.mapUrl {
            self.tasks.append(downloadItemTask(url: mapUrl, type: .video, order: 0))
        }
        
        try addAllSegments(segmentList: videoStream.mediaPlaylist.segmentList, type: M3U8MediaPlaylistTypeVideo, setDuration: true)
        
        self.videoTrack = videoTrack(videoStream: videoStream.streamInfo)
    
        aggregateTrackSize(bitrate: videoStream.streamInfo.bandwidth)
        
        self.selectedAudioStreams.removeAll()
        try addAll(streams: master.audioStreams(), type: M3U8MediaPlaylistTypeAudio)
        self.selectedTextStreams.removeAll()
        try addAll(streams: master.textStreams(), type: M3U8MediaPlaylistTypeSubtitle)

        log.debug("options: \(options)")
        log.debug("videoStream: \(videoStream)")
        log.debug("selectedAudioStreams: \(selectedAudioStreams)")
        log.debug("selectedTextStreams: \(selectedTextStreams)")

        
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
            if line.hasPrefix(M3U8_EXT_X_STREAM_INF) {
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
                    if !line.hasPrefix(M3U8_EXT_X_I_FRAME_STREAM_INF) {
                        reducedLines.append(line)
                    }
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
        try saveOriginal(text: masterText, url: masterUrl, as: MASTER_PLAYLIST_NAME )
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

        try save(text: reducedMasterPlaylist, as: MASTER_PLAYLIST_NAME )        

        // Localize the selected video stream
        try saveMediaPlaylist(videoStream, type: .video)
        
        // Localize the selected audio and text streams
        for stream in selectedAudioStreams {
            try saveMediaPlaylist(stream, type: .audio)
        }

        for stream in selectedTextStreams {
            try saveMediaPlaylist(stream, type: .text)
        }
}
    
    private func isHLSAESKey(line: String) -> Bool {
        return line.hasPrefix(M3U8_EXT_X_KEY) && !line.contains(KEYFORMAT_FAIRPLAY)
    }
    
    private func saveMediaPlaylist<T>(_ stream: Stream<T>, type: DownloadItemTaskType) throws {
        let mediaPlaylist = stream.mediaPlaylist
        let originalUrl = stream.mediaUrl
        let mapUrl = stream.mapUrl
        
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
            
            if line.hasPrefix("#") {
                // Tag
                
                if isHLSAESKey(line: line) {
                    let mediaUrl: URL = segments[i].mediaURL()

                    let updatedLine = rewriteKeyTag(line: line, mediaUrl: mediaUrl)
                    localLines.append(updatedLine)
                    
                } else if line.hasPrefix(M3U8_EXT_X_MAP) {
                    guard let mapUrl = mapUrl else {continue}
                    let localPath = mapUrl.segmentRelativeLocalPath()
                    let localLine = line.replacingOccurrences(of: "URI=\"\(mapUrl)\"", with: "URI=\"\(localPath)\"")
                    print(line, localLine)
                    localLines.append(localLine)

                } else {
                    // Other tags
                    localLines.append(line)
                }
                
                
            } else {
                // Not a tag
                if i < segments.countInt && line == segments[i].uri.absoluteString {
                    localLines.append(segments[i].mediaURL().segmentRelativeLocalPath())
                    i += 1
                } else {
                    localLines.append(line)
                }
            }
        }
        
        let target = originalUrl.mediaPlaylistRelativeLocalPath(as: type)
        try save(text: localLines.joined(separator: "\n") as String, as: target)
    }

    private func rewriteKeyTag(line: String, mediaUrl: URL) -> String { // has AES-128 key replace uri with local path
        let keyAttributes = getSegmentAttributes(fromSegment: line, segmentPrefix: M3U8_EXT_X_KEY, seperatedBy: ",")
        var updatedLine = M3U8_EXT_X_KEY
        for (index, attribute) in keyAttributes.enumerated() {
            var updatedAttribute = attribute
            if attribute.hasPrefix(M3U8_EXT_X_KEY_URI) {
                var mutableAttribute = attribute
                // remove the url attribute tag
                mutableAttribute = mutableAttribute.replacingOccurrences(of: M3U8_EXT_X_KEY_URI + "=", with: "")
                // remove quotation marks
                let uri = mutableAttribute.replacingOccurrences(of: "\"", with: "")
                // create the content url
                guard let url = createContentUrl(from: uri, originalContentUrl: mediaUrl) else { break }
                updatedAttribute = "\(M3U8_EXT_X_KEY_URI)=\"../key/\(url.segmentRelativeLocalPath())\""
            }
            if index != keyAttributes.count - 1 {
                updatedLine.append("\(updatedAttribute),")
            } else {
                updatedLine.append(updatedAttribute)
            }
        }
        return updatedLine
    }

    private func selectVideoStream(master: MasterPlaylist) throws -> VideoStream {
        // The following options affect video stream selection:
//        options?.allowInefficientCodecs (select HEVC even if device does not support it in hardware)
//        options?.videoWidth|videoHeight
//        options?.videoBitrates
//        options?.videoCodecs
        
        // Aliases
        
        typealias Codec = DTGSelectionOptions.VideoCodec
        typealias M3U8Stream = M3U8ExtXStreamInf
        let avc1 = Codec.avc1
        let hevc = Codec.hevc
        let allCodecs = Codec.allCases

        // Utils
        
        func hasCodec(_ s: M3U8Stream, _ codec: String) -> Bool {
            return s.codecs?.contains{($0 as? String)?.hasPrefix(codec) ?? false} ?? false
        }
        
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
                } else {
                    return []
                }
            }
            return filtered
        }
        
        // Check if HEVC should be used. If not, we'll throw away all HEVC streams.
        
        let allowHEVC = CodecSupport.hevc || CodecSupport.softwareHEVC && (options.allowInefficientCodecs ?? false)
        
        let allowAC3 = CodecSupport.ac3
        let allowEC3 = CodecSupport.ec3
        
        // Create a dictionary of streams by codec
        var streams = [Codec: [M3U8Stream]]()
        for c in allCodecs {
            streams[c] = []
        }
        
        // Copy streams from M3U8Kit's structure
        let m3u8Streams = master.videoStreams()
        for i in 0 ..< m3u8Streams.countInt {
            let s = m3u8Streams[i]

            // if the stream uses an audio codec we can't play, skip it.
            if hasCodec(s, "ac-3") && !allowAC3 {
                continue
            } else if hasCodec(s, "ec-3") && !allowEC3{
                continue
            }
            
            // add the stream to the correct array
            if s.codecs == nil || hasCodec(s, "avc1") {
                streams[avc1]?.append(s)
            } else if allowHEVC && hasCodec(s, "hvc1") {
                streams[hevc]?.append(s)
            }
        }
        
        // Filter streams by video HEIGHT and WIDTH
        
        for c in allCodecs {
            if let height = options.videoHeight {
                streams[c] = filter(streams: streams[c]!, 
                                    sortOrder: {$0.resolution.height < $1.resolution.height}, 
                                    filter: { $0.resolution.height >= Float(height) })
            }
            if let width = options.videoWidth {
                streams[c] = filter(streams: streams[c]!, 
                                    sortOrder: {$0.resolution.width < $1.resolution.width}, 
                                    filter: { $0.resolution.width >= Float(width) })
            }
        }
        
        // Filter by bitrate

        for br in options.videoBitrates ?? [] {
            let bitrate: Int
            let codec: Codec
            switch br {
            case .avc1(let value):
                bitrate = value
                codec = avc1
            case .hevc(let value):
                bitrate = value
                codec = hevc
            }

            guard let codecStreams = streams[codec] else { continue }
            streams[codec] = filter(streams: codecStreams, sortOrder: {$0.bandwidth < $1.bandwidth}, filter: {$0.bandwidth >= bitrate})
        }
        
        
        print(streams)

        // Now we have two lists -- hevc and avc1. Look at codec prefs.
        
        func videoStreamWithFirst(of codec: Codec) throws -> VideoStream {
            guard let selected = streams[codec]?.first else {throw HLSLocalizerError.malformedPlaylist}
            return try VideoStream(streamInfo: selected, mediaUrl: selected.m3u8URL(), type: M3U8MediaPlaylistTypeVideo)
        }
        
        // The easy case: only one codec has valid streams. Select the first stream from that codec.
        if streams[avc1]?.isEmpty ?? true {
            return try videoStreamWithFirst(of: hevc)
        } else if streams[hevc]?.isEmpty ?? true {
            return try videoStreamWithFirst(of: avc1)
        }
        
        // Ok, both codecs have valid streams. What does the app prefer?
        if let firstPrefCodec = options.videoCodecs?.first {
            return try videoStreamWithFirst(of: firstPrefCodec)
            
        } else {
            // app did not select -- we'll go with hevc (remember it's not empty)
            return try videoStreamWithFirst(of: hevc)
        }
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
        let lines = stream.mediaPlaylist.originalText.components(separatedBy: .newlines)
        
        var downloadItemTasks = [DownloadItemTask]()
        
        var order = 0
        for line in lines {
            if isHLSAESKey(line: line) {
                order += 1
                
                guard let attr = line.m3u8Attribs(prefix: M3U8_EXT_X_KEY) else {continue}
                
                guard let uri = attr[M3U8_EXT_X_KEY_URI] else {continue}
                guard let url = createContentUrl(from: uri, originalContentUrl: stream.mediaUrl) else {continue}
                
                let task = downloadItemTask(url: url, type: .key, order: order)
                downloadItemTasks.append(task)
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
        // TODO: what about options.audioCodecs?
        
        func canonicalLangList(_ list: [String]?) -> [String] {
            return (list ?? []).map {Locale.canonicalLanguageIdentifier(from: $0)}
        }
        
        guard let streams = streams else { return }
        
        guard type == M3U8MediaPlaylistTypeAudio || type == M3U8MediaPlaylistTypeSubtitle else {
            throw HLSLocalizerError.unknownPlaylistType
        }         
        
        let langList = canonicalLangList(type.isAudio() ? options.audioLanguages : options.textLanguages)
        let allLangs = type.isAudio() ? options.allAudioLanguages : options.allTextLanguages
        
        for i in 0 ..< streams.countInt {
            
            let stream = streams[i]
            
            if let gid = videoTrack?.groupId(for: type) {
                if gid != stream.groupId() { continue }
            }

            // if the stream has a declared language, check if it matches.
            if let lang = stream.language() {
                if !allLangs && !langList.contains(Locale.canonicalLanguageIdentifier(from: lang)) {
                    continue
                }
            }

            let url: URL = stream.m3u8URL()
            do {
                let mediaStream = try MediaStream(streamInfo: stream, mediaUrl: url, type: type)
                try addAllSegments(segmentList: mediaStream.mediaPlaylist.segmentList, type: type)
                
                if type.isAudio() {
                    let bitrate = stream.bandwidth()
                    aggregateTrackSize(bitrate: bitrate > 0 ? bitrate : audioBitrateEstimation)
                    selectedAudioStreams.append(mediaStream)
                } else {
                    selectedTextStreams.append(mediaStream)
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
            tracksInfo.append(TrackInfo(type: type, languageCode: stream.language(), title: stream.name()))
        }
        return tracksInfo
    }
    
    private func getTracksInfo(from streams: [M3U8ExtXMedia], type: TrackInfo.TrackType) -> [TrackInfo] {
        var tracksInfo: [TrackInfo] = []
        for stream in streams {
            tracksInfo.append(TrackInfo(type: type, languageCode: stream.language(), title: stream.name()))
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
    
    func isAudio() -> Bool {
        return self == M3U8MediaPlaylistTypeAudio
    }
    
    func isText() -> Bool {
        return self == M3U8MediaPlaylistTypeSubtitle
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
        return md5WithString(self)
    }
    
    func safeItemPathName() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed) ?? self.md5()
    }
    
    func m3u8Attribs(prefix: String) -> [String:String]? {
        return parseM3U8Attributes(self, prefix)
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
        Video: height=\(videoHeight ?? -1) width=\(videoWidth ?? -1) codecs=\(videoCodecs ?? []) bitrates=\(videoBitrates ?? [])
        Audio: all=\(allAudioLanguages) list=\(audioLanguages ?? []) codecs=\(audioCodecs ?? [])
        Text: all=\(allTextLanguages) list=\(textLanguages ?? [])
        """
    }
}

extension DTGSelectionOptions.VideoCodec: CustomStringConvertible {
    public var description: String {
        switch self {
        case .avc1: return "avc1"
        case .hevc: return "hevc"
        }
    }
}

extension DTGSelectionOptions.AudioCodec: CustomStringConvertible {
    public var description: String {
        switch self {
        case .mp4a: return "mp4a"
        case .ac3: return "ac3"
        case .eac3: return "eac3"
        }
    }
}
