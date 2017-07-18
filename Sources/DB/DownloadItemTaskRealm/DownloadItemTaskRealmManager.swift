//
//  DownloadItemTaskRealmManager.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

/// Manages all actions on `DownloadItemTaskRealm`
class DownloadItemTaskRealmManager: RealmObjectManager {
    typealias RealmObject = DownloadItemTaskRealm
    
    func set(tasks: [DownloadItemTaskRealm]) {
        self.update(tasks)
    }
    
    func tasks(forItemId id: String) -> [DownloadItemTask] {
        return self.get("dtgItemId = '\(id)'").map { $0.asObject() }
    }
    
    func removeTasks(withItemId id: String) {
        let tasksToRemove = self.get("dtgItemId = '\(id)'")
        let realm = try! Realm()
        try! realm.write {
            realm.delete(tasksToRemove)
        }
    }
    
    func remove(_ tasks: [DownloadItemTask]) {
        var tasksToRemove = [DownloadItemTaskRealm]()
        for task in tasks {
            if let taskToRemove: DownloadItemTaskRealm = self.object(for: task.contentUrl.absoluteString) {
                tasksToRemove.append(taskToRemove)
            }
        }
        self.remove(tasksToRemove)
    }
}
