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
    @objc dynamic var languageCode: String = ""
    
    convenience init(trackInfo: TrackInfo) {
        self.init()
        self.title = trackInfo.title
        self.languageCode = trackInfo.languageCode
    }
    
    public override class func shouldIncludeInDefaultSchema() -> Bool { return false } 

    func asTrackInfo() -> TrackInfo {
        return TrackInfo(languageCode: self.languageCode, title: self.title)
    }
}

class DTGItemRealm: Object, RealmObjectProtocol, PrimaryKeyable {
    
    @objc dynamic var id: String = ""
    /// The items's remote URL.
    @objc dynamic var remoteUrl: String = ""
    /// The item's current state.
    @objc dynamic var state: String = ""
    /// Estimated size of the item.
    var estimatedSize = RealmOptional<Int64>()
    /// Downloaded size in bytes.
    @objc dynamic var downloadedSize: Int64 = 0
    
    let availableTextTracks = List<TrackInfoRealm>()
    let availableAudioTracks = List<TrackInfoRealm>()
    let selectedTextTracks = List<TrackInfoRealm>()
    let selectedAudioTracks = List<TrackInfoRealm>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
    public override class func shouldIncludeInDefaultSchema() -> Bool { return false } 
    
    var pk: String {
        return self.id
    }
    
    convenience required init(object: DownloadItem) {
        self.init()
        self.id = object.id
        self.remoteUrl = object.remoteUrl.absoluteString
        self.state = object.state.asString()
        self.estimatedSize = RealmOptional<Int64>(object.estimatedSize)
        self.downloadedSize = object.downloadedSize
        self.availableTextTracks.replaceSubrange(0..<self.availableTextTracks.count, with: object.availableTextTracks.map { TrackInfoRealm(trackInfo: $0) })
        self.availableAudioTracks.replaceSubrange(0..<self.availableAudioTracks.count, with: object.availableAudioTracks.map { TrackInfoRealm(trackInfo: $0) })
        self.selectedTextTracks.replaceSubrange(0..<self.selectedTextTracks.count, with: object.selectedTextTracks.map { TrackInfoRealm(trackInfo: $0) })
        self.selectedAudioTracks.replaceSubrange(0..<self.selectedAudioTracks.count, with: object.selectedAudioTracks.map { TrackInfoRealm(trackInfo: $0) })
    }
    
    static func initialize(with object: DownloadItem) -> DTGItemRealm {
        return DTGItemRealm(object: object)
    }
    
    func asObject() -> DownloadItem {
        let id = self.id
        let remoteUrl = URL(string: self.remoteUrl)!
        var item = DownloadItem(id: id, url: remoteUrl)
        item.state = DTGItemState(value: self.state)!
        item.estimatedSize = self.estimatedSize.value
        item.downloadedSize = self.downloadedSize
        item.availableTextTracks = self.availableTextTracks.map { $0.asTrackInfo() }
        item.availableAudioTracks = self.availableAudioTracks.map { $0.asTrackInfo() }
        item.selectedTextTracks = self.selectedTextTracks.map { $0.asTrackInfo() }
        item.selectedAudioTracks = self.selectedAudioTracks.map { $0.asTrackInfo() }
        
        return item
    }
}
