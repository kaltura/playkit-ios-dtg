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
func getRealm() throws -> Realm {
    return try Realm(configuration: getRealmConfiguration())
}

func getRealmConfiguration() -> Realm.Configuration {
    return Realm.Configuration(
        fileURL: DTGFilePaths.storagePath.appendingPathComponent("downloadToGo.realm"),
        schemaVersion: 1,
        migrationBlock: { migration, oldSchemaVersion in
            // We haven’t migrated anything yet, so oldSchemaVersion == 0
            if (oldSchemaVersion < 1) {
                // The renaming operation should be done outside of calls to `enumerateObjects(ofType: _:)`.
                migration.renameProperty(onType: DownloadItemTaskRealm.className(), from: "trackType", to: "type")
            }
    })
}

protocol DB: class {
    
    /* Items API */
    
    func update(item: DownloadItem) throws
    func item(byId id: String) throws -> DownloadItem?
    func removeItem(byId id: String) throws
    func allItems() throws -> [DownloadItem]
    
    func items(byState state: DTGItemState) throws -> [DownloadItem]
    func update(itemState: DTGItemState, byId id: String) throws
    
    /* Tasks API */
    
    func set(tasks: [DownloadItemTask]) throws
    func tasks(forItemId id: String) throws -> [DownloadItemTask]
    func removeTasks(withItemId id: String) throws
    func remove(_ tasks: [DownloadItemTask]) throws
    func update(_ tasks: [DownloadItemTask]) throws
}

class RealmDB: DB {
    
    fileprivate let dtgItemRealmManager = DTGItemRealmManager()
    fileprivate let downloadItemTaskRealmManager = DownloadItemTaskRealmManager()
}

/************************************************************/
// MARK: - DB API - Items
/************************************************************/

extension RealmDB {
    
    func update(item: DownloadItem) throws {
        try self.dtgItemRealmManager.update([item])
    }
    
    func item(byId id: String) throws -> DownloadItem? {
        return try self.dtgItemRealmManager.object(for: id)
    }
    
    func removeItem(byId id: String) throws {
        guard let objectToRemove: DTGItemRealm = try self.dtgItemRealmManager.object(for: id) else { return }
        try self.dtgItemRealmManager.cascadeDelete([objectToRemove])
    }
    
    func allItems() throws -> [DownloadItem] {
        return try self.dtgItemRealmManager.allObjects()
    }
    
    func items(byState state: DTGItemState) throws -> [DownloadItem] {
        return try self.dtgItemRealmManager.allObjects().filter { $0.state == state }
    }
    
    func update(itemState: DTGItemState, byId id: String) throws {
        guard var item = try self.dtgItemRealmManager.object(for: id) else { return }
        item.state = itemState
        try self.dtgItemRealmManager.update([item])
    }
}

/************************************************************/
// MARK: - DB API - Tasks
/************************************************************/

extension RealmDB {
    
    func set(tasks: [DownloadItemTask]) throws {
        let realmTasks = tasks.map { DownloadItemTaskRealm(object: $0) }
        try self.downloadItemTaskRealmManager.set(tasks: realmTasks)
    }
    
    func tasks(forItemId id: String) throws -> [DownloadItemTask] {
        return try self.downloadItemTaskRealmManager.tasks(forItemId: id)
    }
    
    func removeTasks(withItemId id: String) throws {
        try self.downloadItemTaskRealmManager.removeTasks(withItemId: id)
    }
    
    func remove(_ tasks: [DownloadItemTask]) throws {
        try self.downloadItemTaskRealmManager.remove(tasks)
    }
    
    func update(_ tasks: [DownloadItemTask]) throws {
        try self.downloadItemTaskRealmManager.update(tasks)
    }
}
