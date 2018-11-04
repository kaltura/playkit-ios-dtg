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

class DownloadItemTaskRealm: Object {
    
    @objc dynamic var dtgItemId: String = ""
    
    @objc dynamic var contentUrl: String = ""

    @objc dynamic var type: String = ""

    /// The destination to save the download item to.
    @objc dynamic var destinationUrl: String = ""
    
    @objc dynamic var resumeData: Data? = nil
    
    let order = RealmOptional<Int>()
    
    override static func primaryKey() -> String? {
        return "destinationUrl"
    }
    
    public override class func shouldIncludeInDefaultSchema() -> Bool { return false } 
    
    convenience init(object: DownloadItemTask) {
        self.init()
        self.dtgItemId = object.dtgItemId
        self.contentUrl = object.contentUrl.absoluteString
        self.type = object.type.asString()
        self.destinationUrl = DownloadItemTaskRealm.relativeDestUrl(object)
        self.resumeData = object.resumeData
        self.order.value = object.order
    }
    
    static func relativeDestUrl(_ obj: DownloadItemTask) -> String {
        return String(obj.destinationUrl.absoluteString[DTGFilePaths.storagePath.absoluteString.endIndex...])
    } 
    
    func asObject() -> DownloadItemTask {
        let contentUrl = URL(string: self.contentUrl)!
        let type = DownloadItemTaskType(type: self.type)!
        let destinationUrl = URL(string: self.destinationUrl, relativeTo: DTGFilePaths.storagePath)!
        var downloadItemTask = DownloadItemTask(dtgItemId: self.dtgItemId, contentUrl: contentUrl, type: type, 
                                                destinationUrl: destinationUrl, order: order.value)
        if let resumeData = self.resumeData {
            downloadItemTask.resumeData = resumeData
        }
        
        return downloadItemTask
    }
}
