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
    return try Realm(configuration: config)
}

fileprivate func migrate_to_3(_ migration: Migration) {
    
    // In schema v2, DTGItemRealm had 4 lists of TrackInfoRealm objects:
    // selectedTextTracks, availableTextTracks, selectedAudioTracks, availableAudioTracks
    // As a model, it was wrong: all of the `selected` tracks are also `available`.
    
    // In addition, each write to the DTGItemRealm created a leak of TrackInfoRealm objects: the list of objects
    // that existed before the write was removed from the DTGItemRealm object, but NOT DELETED FROM DB. And new
    // lists were created.
    
    // In schema v2 DTGItemRealm only has 2 such lists: textTracks and audioTracks.
    // Instead of the redundant `selected` lists, each TrackInfoRealm object now has a boolean property, `selected`.
    // In addition, TrackInfoRealm also has a type propery (audio/text).
    
    // The following code makes the upgrade: it goes over the lists of the TrackInfoRealm objects that are currently
    // associated with the DTGItemRealm objects. It creates new TrackInfoRealm objects with the correct properties
    // and assumes that all `available` tracks are also `selected`: this is true because DTG does not currently let
    // the app choose tracks, it selects all of them. The new TrackInfoRealm objects are added to the object's 
    // textTracks and audioTracks lists.
    
    
    migration.enumerateObjects(ofType: DTGItemRealm.className()) { (oldObj, newObj) in
        guard let newObj = newObj, let oldObj = oldObj else {return}

        let names = [
            (TrackInfo.TrackType.text, "selectedTextTracks", "textTracks"), 
            (TrackInfo.TrackType.audio, "selectedAudioTracks", "audioTracks")
        ]
        
        for (type, oldName, newName) in names {

            let oldTracks = oldObj[oldName] as! List<DynamicObject>
            let newTracks = List<TrackInfoRealm>()
            
            for t in oldTracks {
                let ti = TrackInfo(type: type, 
                                   languageCode: t["languageCode"] as? String ?? "?", 
                                   title: t["title"] as? String ?? "?")
                let tir = TrackInfoRealm(trackInfo: ti, selected: true)
                newTracks.append(tir)
            }
            
            newObj[newName] = newTracks
        }
    }
    
    // Delete all OLD TrackInfoRealm objects (created new objects in the previous step)
    migration.enumerateObjects(ofType: TrackInfoRealm.className()) { (oldObj, _) in
        guard let oldObj = oldObj else {return}
        
        migration.delete(oldObj)
    }
}



fileprivate let config = Realm.Configuration(
    fileURL: DTGFilePaths.storagePath.appendingPathComponent("downloadToGo.realm"),
    schemaVersion: 5,
    migrationBlock: { migration, oldSchemaVersion in
        
        // We haven’t migrated anything yet, so oldSchemaVersion == 0
        if (oldSchemaVersion < 1) {
            // The renaming operation should be done outside of calls to `enumerateObjects(ofType: _:)`.
            migration.renameProperty(onType: DownloadItemTaskRealm.className(), from: "trackType", to: "type")
        }
        
        // 1 -> 2
        if (oldSchemaVersion < 2) {
            // nothing to do just detect new properties on realm item
        }
        
        // 2 -> 3
        if (oldSchemaVersion == 2) {    
            // TrackInfo object were only added in schema 2 so this migration is not required if old is 0 or 1
            migrate_to_3(migration)
        }
        
        // 3 -> 4
        if (oldSchemaVersion < 4) {
            // Primary key for DownloadItemTaskRealm has changed, nothing to do
        }
        
        // 4 -> 5
        if (oldSchemaVersion < 5) {
            // Property 'TrackInfoRealm.languageCode' has been made optional. Nothing to do.
        }
    },
    objectTypes: [DTGItemRealm.self, DownloadItemTaskRealm.self, TrackInfoRealm.self]
)

class RealmDB {
    func write(_ rlm: Realm, _ block: (() throws -> Void)) throws {
        try autoreleasepool {
            try rlm.write {
                try block()
            }
        }
    }

}

/************************************************************/
// MARK: - DB API - Items
/************************************************************/

extension RealmDB {
    
    func convertTracks(itemId: String, type: TrackInfo.TrackType, available: [TrackInfo], selected: [TrackInfo], list: List<TrackInfoRealm>) {
        var tracks = [TrackInfo: Bool]()
        
        for t in available {
            tracks[t] = false
        }
        for t in selected {
            tracks[t] = true
        }

        for (key, value) in tracks {
            list.append(TrackInfoRealm(trackInfo: key, selected: value))
        }
    }
    
    func updateAfterMetadataLoaded(item: DownloadItem) throws {
        guard let realmItem = try getRealm().object(ofType: DTGItemRealm.self, forPrimaryKey: item.id) else {
            log.error("No such item \(item.id)")
            return
        }
        
        try write(getRealm()) {
            realmItem.state = DTGItemState.metadataLoaded.asString()
            realmItem.duration.value = item.duration
            realmItem.estimatedSize.value = item.estimatedSize ?? -1
            convertTracks(itemId: item.id, type: .text, available: item.availableTextTracks, selected: item.selectedTextTracks, list: realmItem.textTracks)
            convertTracks(itemId: item.id, type: .audio, available: item.availableAudioTracks, selected: item.selectedAudioTracks, list: realmItem.audioTracks)
        }
    }
    
    func add(item: DownloadItem) throws {
        let rlm = try getRealm()
        try write(rlm) {
            if rlm.object(ofType: DTGItemRealm.self, forPrimaryKey: item.id) != nil {
                throw DTGError.invalidState(itemId: item.id)
            }
            rlm.add(DTGItemRealm(object: item))
        }
    }
    
    func realmItem(_ id: String) throws -> DTGItemRealm? {
        guard let item = try getRealm().object(ofType: DTGItemRealm.self, forPrimaryKey: id) else {
            return nil
        }
        return item
    }
    
    func realmItems(_ predicateFormat: String, _ args: Any) throws -> Results<DTGItemRealm> {
        return try getRealm().objects(DTGItemRealm.self).filter(predicateFormat, args)
    }
    
    func getItem(byId id: String) throws -> DownloadItem? {
        guard let item = try realmItem(id) else { return nil }
        
        return item.asObject()
    }
    
    func updateItemSize(id: String, incrementDownloadSize: Int64, state: DTGItemState?) throws -> (newSize: Int64, estSize: Int64) {

        guard let realmItem = try realmItem(id) else {
            log.error("No such item \(id)")
            return (-1, -1)
        }
        
        try write(getRealm()) {
            if realmItem.isInvalidated {
                return
            } 
            realmItem.downloadedSize += incrementDownloadSize
            if let state = state {
                realmItem.state = state.asString()
            }
        }
        
        return realmItem.isInvalidated ? (-1, -1) : (realmItem.downloadedSize, realmItem.estimatedSize.value ?? -1)
    }

    func removeItem(byId id: String) throws {
        try deleteItemWithCascade(id: id)
    }
    
    func deleteItemWithCascade(id: String) throws {
        let rlm = try getRealm() 
        
        guard let item = rlm.object(ofType: DTGItemRealm.self, forPrimaryKey: id) else {
            log.error("Nothing to delete, no such item \(id)")
            return
        }
        
        try write(rlm) {
            // first remove all related download item tasks
            RealmDB.removeTasks(withItemId: item.id, rlm: rlm)
            
            rlm.delete(item.audioTracks)
            rlm.delete(item.textTracks)
            
            // remove the object itself
            rlm.delete(item)
        }
    }
    
    
    func getItems(byState state: DTGItemState) throws -> [DownloadItem] {
        let items = try realmItems("state = %@", state.asString())
        return items.map({ $0.asObject() })
    }
    
    @discardableResult
    func updateItemState(id: String, newState: DTGItemState) throws -> Bool {
        guard let item = try self.realmItem(id) else {
            log.error("No such item \(id)")
            return false
        }
        
        let oldStateStr = item.state
        let oldState = DTGItemState(value: oldStateStr)
        
        if oldState != newState {
            try write(getRealm()) {
                item.state = newState.asString()
            }
            return true
        }
        
        return false
    }
}

/************************************************************/
// MARK: - DB API - Tasks
/************************************************************/

extension RealmDB {
    
    func set(tasks: [DownloadItemTask]) throws {
        let realmTasks = tasks.map { DownloadItemTaskRealm(object: $0) }
        let rlm = try getRealm()
        try write(rlm) {
            for t in realmTasks {
                if let et = rlm.object(ofType: DownloadItemTaskRealm.self, forPrimaryKey: t.destinationUrl) {
                    log.warning("Task with key \(et.destinationUrl) already exists (item=\(et.dtgItemId) url=\(et.contentUrl) type=\(et.type))")
                } else {
                    rlm.add(t, update: true)    // Using update so it won't crash if exists
                }
            }
        }
    }
    
    func getTasks(forItemId id: String) throws -> [DownloadItemTask] {
        let realmTasks = try RealmDB.getTasks(itemId: id, rlm: getRealm()).sorted(byKeyPath: "order")
        return realmTasks.map({$0.asObject()})
    }
    
    func removeTasks(withItemId id: String) throws {
        let rlm = try getRealm()
        try write(rlm) {
            RealmDB.removeTasks(withItemId: id, rlm: rlm)
        }
    }
    
    static func removeTasks(withItemId id: String, rlm: Realm) {
        // Assuming we're already in transaction
        rlm.delete(getTasks(itemId: id, rlm: rlm))
    }
    
    static func getTasks(itemId id: String, rlm: Realm) -> Results<DownloadItemTaskRealm> {
        return rlm.objects(DownloadItemTaskRealm.self).filter("dtgItemId=%@", id)
    }
    
    func removeTask(_ task: DownloadItemTask) throws {
        let rlm = try getRealm()
        guard let realmTask = rlm.object(ofType: DownloadItemTaskRealm.self, 
                                         forPrimaryKey: DownloadItemTaskRealm.relativeDestUrl(task)) else {
            log.error("No such task \(task.destinationUrl)")
            return
        }
        
        try write(rlm) {
            rlm.delete(realmTask)
        }
    }
    
    func pauseTasks(_ tasks: [DownloadItemTask]) throws {
        let rlm = try getRealm()
        try write(rlm) {
            for t in tasks {
                if let rt = rlm.object(ofType: DownloadItemTaskRealm.self, 
                                       forPrimaryKey: DownloadItemTaskRealm.relativeDestUrl(t)) {
                    rt.resumeData = t.resumeData
                }
            }
        }
    }
}
