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

/// Manages all actions on `DTGItemRealm`
class DTGItemRealmManager: RealmObjectManager, RealmCascadeDeleteable {
    typealias RealmObject = DTGItemRealm
    
    /************************************************************/
    // MARK: - RealmCascadeDeleteable
    /************************************************************/
    
    func cascadeDelete(_ objects: [RealmObject]) throws {
        // first remove all related download item tasks
        for object in objects {
            let downloadItemTaskRealmManager = DownloadItemTaskRealmManager()
            try downloadItemTaskRealmManager.removeTasks(withItemId: object.id)
        }
        // remove the object itself
        try self.remove(objects)
    }
}
