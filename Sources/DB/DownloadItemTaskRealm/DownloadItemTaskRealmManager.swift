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

/// Manages all actions on `DownloadItemTaskRealm`
class DownloadItemTaskRealmManager: RealmObjectManager {
    typealias RealmObject = DownloadItemTaskRealm
    
    func set(tasks: [DownloadItemTaskRealm]) throws {
        try self.update(tasks)
    }
    
    func tasks(forItemId id: String) throws -> [DownloadItemTask] {
        return try self.get("dtgItemId = '\(id)'").map { $0.asObject() }
    }
    
    func removeTasks(withItemId id: String) throws {
        let tasksToRemove = try self.get("dtgItemId = '\(id)'")
        try autoreleasepool { 
            let realm = try getRealm()
            try realm.write {
                realm.delete(tasksToRemove)
            }
        }
    }
    
    func remove(_ tasks: [DownloadItemTask]) throws {
        var tasksToRemove = [DownloadItemTaskRealm]()
        for task in tasks {
            if let taskToRemove: DownloadItemTaskRealm = try self.object(for: task.contentUrl.absoluteString) {
                tasksToRemove.append(taskToRemove)
            }
        }
        try self.remove(tasksToRemove)
    }
}
