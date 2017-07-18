//
//  DownloadItemTaskRealm.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

class DownloadItemTaskRealm: Object, RealmObjectProtocol, PrimaryKeyable {
    
    dynamic var dtgItemId: String = ""
    
    dynamic var contentUrl: String = ""

    dynamic var trackType: String = ""
    /// The destination to save the download item to.
    dynamic var destinationUrl: String = ""
    
    dynamic var resumeData: Data? = nil
    
    override static func primaryKey() -> String? {
        return "contentUrl"
    }
    
    var pk: String {
        return self.contentUrl
    }
    
    convenience init(object: DownloadItemTask) {
        self.init()
        self.dtgItemId = object.dtgItemId
        self.contentUrl = object.contentUrl.absoluteString
        self.trackType = object.trackType.asString()
        self.destinationUrl = object.destinationUrl.absoluteString.substring(from: DTGSharedContentManager.storagePath.absoluteString.endIndex) // FIXME: change this to the relative path
        self.resumeData = object.resumeData
    }
    
    static func initialize(with object: DownloadItemTask) -> DownloadItemTaskRealm {
        return DownloadItemTaskRealm(object: object)
    }
    
    func asObject() -> DownloadItemTask {
        let contentUrl = URL(string: self.contentUrl)!
        let trackType = DTGTrackType(type: self.trackType)!
        let destinationUrl = URL(string: self.destinationUrl, relativeTo: DTGSharedContentManager.storagePath)! // FIXME: change this to the full path from relative path
        var downloadItemTask = DownloadItemTask(dtgItemId: self.dtgItemId, contentUrl: contentUrl, trackType: trackType, destinationUrl: destinationUrl)
        if let resumeData = self.resumeData {
            downloadItemTask.resumeData = resumeData
        }
        
        return downloadItemTask
    }
}
