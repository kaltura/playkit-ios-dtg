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
import PlayKitUtils


let KEYFORMAT_FAIRPLAY =    M3U8_EXT_X_KEY_KEYFORMAT + "=\"com.apple.streamingkeydelivery\""
let MASTER_PLAYLIST_NAME =  "master.m3u8"


class HLSLocalizer {
    
    
    let itemId: String
    let masterUrl: URL
    let downloadPath: URL
    let options: DTGSelectionOptions
    
    var tasks = [DownloadItemTask]()
    var duration: Double = Double.nan
    var estimatedSize: Int64?
    
    var videoTrack: VideoTrack?
    
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
    
    private func videoTrack(videoStream: M3U8ExtXStreamInf) -> VideoTrack {
        return VideoTrack(width: Int(videoStream.resolution.width), 
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

        guard let videoStream = self.selectedVideoStream else { throw HLSLocalizerError.invalidState }
                
        var localMaster = [M3U8_EXTM3U]
        
        localMaster.append(contentsOf: extraMasterTags(text: masterText))
        
        localMaster.append(videoStream.localMasterLine(hasAudio: selectedAudioStreams.count > 0, hasText: selectedTextStreams.count > 0))
        
        for stream in selectedAudioStreams {
            localMaster.append(stream.localMasterLine())
        }
        for stream in selectedTextStreams {
            localMaster.append(stream.localMasterLine())
        }
        
        try save(text: localMaster.joined(separator: "\n") + "\n", as: MASTER_PLAYLIST_NAME)
        
        // Localize the selected video stream
        try saveMediaPlaylist(videoStream, forceVideo: true)
        
        // Localize the selected audio and text streams
        for stream in selectedAudioStreams {
            try saveMediaPlaylist(stream)
        }

        for stream in selectedTextStreams {
            try saveMediaPlaylist(stream)
        }
    }
    
    private func extraMasterTags(text: String) -> [String] {
        let reader = M3U8LineReader(text: text)
        var lines = [String]()
        while true {
            guard let line = reader?.next() else {break}
            
            if isFairPlaySessionKey(line: line) {
                lines.append(line)
            }
        }
        return lines
    }
    
    private func isHLSAESKey(line: String) -> Bool {
        return line.hasPrefix(M3U8_EXT_X_KEY) && !line.contains(KEYFORMAT_FAIRPLAY)
    }
    
    private func isFairPlaySessionKey(line: String) -> Bool {
        return line.hasPrefix("#EXT-X-SESSION-KEY:") && line.contains(KEYFORMAT_FAIRPLAY)
    }
    
    private func saveMediaPlaylist<T>(_ stream: Stream<T>, forceVideo: Bool = false) throws {
        let mediaPlaylist = stream.mediaPlaylist
        let originalUrl = stream.mediaUrl
        let mapUrl = stream.mapUrl
        let type = forceVideo ? DownloadItemTaskType.video : stream.trackType
        
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
        //options?.allowInefficientCodecs (select HEVC even if device does not support it in hardware)
        //options?.videoWidth|videoHeight
        //options?.videoBitrates
        //options?.videoCodecs
                        
        let videoCodecs = TrackCodec.videoCodecs.map { $0.tag }
        let audioCodecs = TrackCodec.audioCodecs.map { $0.tag }
        let allCodecs = videoCodecs + audioCodecs

        // Create a dictionary of streams by codec.
        // ONLY THE MAIN STREAMS are included -- not the alternates.
        var mainStreams = [CodecTag: [M3U8Stream]]()
        for c in allCodecs {
            mainStreams[c] = []
        }
        
        // Copy streams from M3U8Kit's structure
        let m3u8Streams = master.videoStreams()
        m3u8Streams.sortByBandwidth(inOrder: .orderedAscending)
        
        var hasVideo = false
        var hasAudio = false
        var hasResolution = false
        
        for i in 0 ..< m3u8Streams.countInt {
            let s = m3u8Streams[i]

            // if the stream uses a codec we can't play, skip it.
            if s.usesUnsupportedCodecs(with: options) {
                continue
            }
            
            if s.resolution.height > 0 && s.resolution.width > 0 {
                hasResolution = true
            }
            
            // add the stream to the correct array
            if s.codecs == nil {
                // If no codec is specified, assume avc1/mp4a
                mainStreams[TrackCodec.avc1.tag]?.append(s)
                hasVideo = true
                
            } else if let videoCodec = s.videoCodec() {
                // A video codec was specified
                mainStreams[videoCodec]?.append(s)
                hasVideo = true
                
            } else if let audioCodec = s.audioCodec() {
                // An audio codec was specified with no video codec
                mainStreams[audioCodec]?.append(s)
                hasAudio = true
            }
        }
                
        
        #if DEBUG
        print("Playable video streams:", mainStreams)
        #endif

        
        // Filter streams by video HEIGHT and WIDTH
        
        if hasResolution {  // Don't sort/filter by resolution if not set
            for c in videoCodecs {
                if let height = options.videoHeight {
                    mainStreams[c] = filter(streams: mainStreams[c]!, 
                                            sortOrder: {$0.resolution.height < $1.resolution.height}, 
                                            filter: { $0.resolution.height >= Float(height) })
                }
                if let width = options.videoWidth {
                    mainStreams[c] = filter(streams: mainStreams[c]!, 
                                            sortOrder: {$0.resolution.width < $1.resolution.width}, 
                                            filter: { $0.resolution.width >= Float(width) })
                }
            }
        }
        
        
        // Filter by bitrate
        var videoBitrates = options.videoBitrates
        if videoBitrates[.avc1] == nil {
            videoBitrates[.avc1] = 180_000
        }
        if videoBitrates[.hevc] == nil {
            videoBitrates[.hevc] = 120_000
        }
        
        for (codec, bitrate) in videoBitrates {
            guard let codecStreams = mainStreams[codec.tag] else { continue }
            mainStreams[codec.tag] = filter(streams: codecStreams, sortOrder: {$0.bandwidth < $1.bandwidth}, filter: {$0.bandwidth >= bitrate})
        }

        
        #if DEBUG
        print("Filtered video streams:", mainStreams)
        #endif

        
        if hasVideo {
            for codec in options.fullVideoCodecPriority() {
                if let codecStreams = mainStreams[codec], let first = codecStreams.first {
                    return try VideoStream(streamInfo: first, mediaUrl: first.m3u8URL(), type: M3U8MediaPlaylistTypeVideo)
                }
            }
        } else if hasAudio {
            for codec in options.fullAudioCodecPriority() {
                if let codecStreams = mainStreams[codec], let first = codecStreams.first {
                    return try VideoStream(streamInfo: first, mediaUrl: first.m3u8URL(), type: M3U8MediaPlaylistTypeAudio)
                }
            }
        }
        throw HLSLocalizerError.malformedPlaylist
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
                if let mapUrl = mediaStream.mapUrl {
                    self.tasks.append(downloadItemTask(url: mapUrl, type: mediaStream.trackType, order: 0))
                }
                
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
