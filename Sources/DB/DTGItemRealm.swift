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
import RealmSwift

class TrackInfoRealm: Object {
    @objc dynamic var title: String = ""
    @objc dynamic var languageCode: String?     // HLS LANGUAGE is optional
    @objc dynamic var type: String = ""
    @objc dynamic var selected = false
    
    convenience init(trackInfo: TrackInfo, selected: Bool) {
        self.init()
        
        self.title = trackInfo.title
        self.languageCode = trackInfo.languageCode
        self.type = trackInfo.type.rawValue
        self.selected = selected
    }
    
    
    public override class func shouldIncludeInDefaultSchema() -> Bool { return false } 

    func asTrackInfo() -> TrackInfo? {
        guard let trackType = TrackInfo.TrackType(rawValue: type) else {
            log.error("No such type \(type)")
            return nil
        }
        return TrackInfo(type: trackType, 
                         languageCode: self.languageCode, 
                         title: self.title)
    }
}

class DTGItemRealm: Object {
    
    @objc dynamic var id: String = ""
    /// The items's remote URL.
    @objc dynamic var remoteUrl: String = ""
    /// The item's current state.
    @objc dynamic var state: String = ""
    /// Estimated size of the item.
    var estimatedSize = RealmOptional<Int64>()
    /// Downloaded size in bytes.
    @objc dynamic var downloadedSize: Int64 = 0
    
    var duration = RealmOptional<TimeInterval>()

    let textTracks = List<TrackInfoRealm>()
    let audioTracks = List<TrackInfoRealm>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
    public override class func shouldIncludeInDefaultSchema() -> Bool { return false } 
    
    convenience required init(object: DownloadItem) {
        self.init()
        self.id = object.id
        self.remoteUrl = object.remoteUrl.absoluteString
        self.state = object.state.asString()
    }
    
    func asObject() -> DownloadItem {
        let id = self.id
        let remoteUrl = URL(string: self.remoteUrl)!
        var item = DownloadItem(id: id, url: remoteUrl)
        item.state = DTGItemState(value: self.state)!
        item.duration = self.duration.value
        item.estimatedSize = self.estimatedSize.value
        item.downloadedSize = self.downloadedSize
        item.availableTextTracks = self.textTracks.filter("type = 'text'").compactMap({ $0.asTrackInfo() })
        item.selectedTextTracks = self.textTracks.filter("type = 'text' AND selected = true").compactMap({ $0.asTrackInfo() })
        item.availableAudioTracks = self.audioTracks.filter("type = 'audio'").compactMap({ $0.asTrackInfo() })
        item.selectedAudioTracks = self.audioTracks.filter("type = 'audio' AND selected = true").compactMap({ $0.asTrackInfo() })
        
        return item
    }
}
