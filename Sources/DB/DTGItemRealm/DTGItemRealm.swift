//
//  DTGItemRealm.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

class DTGItemRealm: Object, RealmObjectProtocol, PrimaryKeyable {
    
    dynamic var id: String = ""
    /// The items's remote URL.
    dynamic var remoteUrl: String = ""
    /// The item's current state.
    dynamic var state: String = ""
    /// Estimated size of the item.
    var estimatedSize = RealmOptional<Int64>()
    /// Downloaded size in bytes.
    dynamic var downloadedSize: Int64 = 0
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
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
        let remoteUrl = URL(string: self.remoteUrl, relativeTo: DTGSharedContentManager.storagePath)! // FIXME: make sure it works
        var item = DownloadItem(id: id, url: remoteUrl)
        item.state = DTGItemState(value: self.state)!
        item.estimatedSize = self.estimatedSize.value
        item.downloadedSize = self.downloadedSize

        return item
    }
}
