//
//  DB.swift
//  Pods
//
//  Created by Gal Orlanczyk on 17/07/2017.
//
//

import Foundation

protocol DB_API {
    static var shared: DB_API { get }
    
    /* Items API */
    func update(item: DownloadItem)
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

class DB: DB_API {
    /// The singleton shared db instance
    static let shared: DB_API = DB()
    private init() {}
    
    /// Dispatch queue to handle all db actions on a background queue to make sure not block main.
    fileprivate let dispatch = DispatchQueue(label: "com.kaltura.dtg.db.dispatch")
    
    fileprivate let dtgItemRealmManager = DTGItemRealmManager()
    
    fileprivate let downloadItemTaskRealmManager = DownloadItemTaskRealmManager()
}

/************************************************************/
// MARK: - DB API - Items
/************************************************************/

extension DB {
    
    func update(item: DownloadItem) {
        return self.dispatch.sync {
            let oldItem = self.dtgItemRealmManager.object(for: item.id)
            if oldItem?.state != item.state {
                // update state change to the item delegate
                DTGSharedContentManager.itemDelegate?.item(id: item.id , didChangeToState: item.state)
            }
            return self.dtgItemRealmManager.update([item])
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
            return self.allItems().filter { $0.state == state }
        }
    }
    
    func update(itemState: DTGItemState, byId id: String) {
        self.dispatch.sync {
            guard var item = self.dtgItemRealmManager.object(for: id) else { return }
            item.state = itemState
            self.dtgItemRealmManager.update([item])
            // update state change to the item delegate
            DTGSharedContentManager.itemDelegate?.item(id: id , didChangeToState: itemState)
        }
    }
}

/************************************************************/
// MARK: - DB API - Tasks
/************************************************************/

extension DB {
    
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
