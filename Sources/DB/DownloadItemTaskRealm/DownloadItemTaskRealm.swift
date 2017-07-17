//
//  DownloadItemTaskRealm.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

class DownloadItemTaskRealm: Object, RealmObjectProtocol {
    
    dynamic var contentUrl: String = ""
    dynamic var trackType: String = ""
    /// The destination to save the download item to.
    dynamic var destinationUrl: String = ""
    
    dynamic var resumeData: Data? = nil
    
    let dtgItem = LinkingObjects(fromType: DTGItemRealm.self, property: "downloadItemTasks")
    
    override static func primaryKey() -> String? {
        return "contentUrl"
    }
    
    convenience init(object: DownloadItemTask) {
        self.init()
        self.contentUrl = object.contentUrl.absoluteString
        self.trackType = object.trackType.asString()
        self.destinationUrl = object.destinationUrl.absoluteString.substring(to: DTGSharedContentManager.storagePath.absoluteString.endIndex) // FIXME: change this to the relative path
        self.resumeData = object.resumeData
    }
    
    static func initialize(with object: DownloadItemTask) -> DownloadItemTaskRealm {
        return DownloadItemTaskRealm(object: object)
    }
    
    func asObject() -> DownloadItemTask {
        let contentUrl = URL(string: self.contentUrl)!
        let trackType = DTGTrackType(type: self.trackType)!
        let destinationUrl = URL(string: self.destinationUrl, relativeTo: DTGSharedContentManager.storagePath)! // FIXME: change this to the full path from relative path
        var downloadItemTask = DownloadItemTask(contentUrl: contentUrl, trackType: trackType, destinationUrl: destinationUrl)
        if let resumeData = self.resumeData {
            downloadItemTask.resumeData = resumeData
        }
        
        return downloadItemTask
    }
}
