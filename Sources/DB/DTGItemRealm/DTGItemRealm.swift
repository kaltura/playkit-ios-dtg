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
        
        if let tracks = try? ContentManager.shared.itemTracks(id: self.id) {
            item.selectedAudioTracks = tracks.audio
            item.selectedTextTracks = tracks.text
        }
        
        return item
    }
}
