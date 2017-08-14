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

/// returns a configured realm object.
func getRealm() -> Realm {
    return try! Realm(configuration: Realm.Configuration(fileURL: DTGFilePaths.storagePath.appendingPathComponent("downloadToGo.realm")))
}

protocol DB: class {
    
    /* Items API */
    
    func update(item: DownloadItem, completionHandler: (() -> Void)?)
    func item(byId id: String) -> DownloadItem?
    func removeItem(byId id: String)
    func allItems() -> [DownloadItem]
    
    func items(byState state: DTGItemState) -> [DownloadItem]
    func update(itemState: DTGItemState, byId id: String)
    
    /* Tasks API */
    
    func set(tasks: [DownloadItemTask])
    func tasks(forItemId id: String) -> [DownloadItemTask]
    func removeTasks(withItemId id: String)
    func remove(_ tasks: [DownloadItemTask])
    func update(_ tasks: [DownloadItemTask])
}

class RealmDB: DB {
    
    fileprivate let dtgItemRealmManager = DTGItemRealmManager()
    fileprivate let downloadItemTaskRealmManager = DownloadItemTaskRealmManager()
    
    /// Dispatch queue to handle all actions on a background queue to make sure not to block main thread.
    /// use only for db actions and to synchornized changes
    let dispatch = DispatchQueue(label: "com.kaltura.dtg.db")
}

/************************************************************/
// MARK: - DB API - Items
/************************************************************/

extension RealmDB {
    
    func update(item: DownloadItem, completionHandler: (() -> Void)?) {
        self.dispatch.sync {
            self.dtgItemRealmManager.update([item])
            completionHandler?()
        }
    }
    
    func item(byId id: String) -> DownloadItem? {
        return self.dispatch.sync {
            return self.dtgItemRealmManager.object(for: id)
        }
    }
    
    func removeItem(byId id: String) {
        self.dispatch.sync {
            guard let objectToRemove: DTGItemRealm = self.dtgItemRealmManager.object(for: id) else { return }
            self.dtgItemRealmManager.cascadeDelete([objectToRemove])
        }
    }
    
    func allItems() -> [DownloadItem] {
        return self.dispatch.sync {
            return self.dtgItemRealmManager.allObjects()
        }
    }
    
    func items(byState state: DTGItemState) -> [DownloadItem] {
        return self.dispatch.sync {
            return self.dtgItemRealmManager.allObjects().filter { $0.state == state }
        }
    }
    
    func update(itemState: DTGItemState, byId id: String) {
        self.dispatch.sync {
            guard var item = self.dtgItemRealmManager.object(for: id) else { return }
            item.state = itemState
            self.dtgItemRealmManager.update([item])
        }
    }
}

/************************************************************/
// MARK: - DB API - Tasks
/************************************************************/

extension RealmDB {
    
    func set(tasks: [DownloadItemTask]) {
        self.dispatch.sync {
            let realmTasks = tasks.map { DownloadItemTaskRealm(object: $0) }
            self.downloadItemTaskRealmManager.set(tasks: realmTasks)
        }
    }
    
    func tasks(forItemId id: String) -> [DownloadItemTask] {
        return self.dispatch.sync {
            return self.downloadItemTaskRealmManager.tasks(forItemId: id)
        }
    }
    
    func removeTasks(withItemId id: String) {
        self.dispatch.sync {
            self.downloadItemTaskRealmManager.removeTasks(withItemId: id)
        }
    }
    
    func remove(_ tasks: [DownloadItemTask]) {
        self.dispatch.sync {
            self.downloadItemTaskRealmManager.remove(tasks)
        }
    }
    
    func update(_ tasks: [DownloadItemTask]) {
        self.dispatch.sync {
            self.downloadItemTaskRealmManager.update(tasks)
        }
    }
}
