//
//  DTGItemRealmManager.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

/// Manages all actions on `DTGItemRealm`
class DTGItemRealmManager: RealmObjectManager, RealmCascadeDeleteable {
    typealias RealmObject = DTGItemRealm
    
    /************************************************************/
    // MARK: - RealmCascadeDeleteable
    /************************************************************/
    
    func cascadeDelete(_ objects: [RealmObject]) {
        // first remove all related download item tasks
        for object in objects {
            let downloadItemTaskRealmManager = DownloadItemTaskRealmManager()
            downloadItemTaskRealmManager.removeTasks(withItemId: object.id)
        }
        // remove the object itself
        self.remove(objects)
    }
}
