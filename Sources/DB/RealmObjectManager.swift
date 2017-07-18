//
//  ObjectRealmManager.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

protocol RealmObjectManager {
    associatedtype RealmObject: Object
}

extension RealmObjectManager {
    
    func update(_ objects: [RealmObject]) {
        let realm = try! Realm()
        try! realm.write {
            realm.add(objects, update: true)
        }
    }
    
    func remove(_ objects: [RealmObject]) {
        let realm = try! Realm()
        try! realm.write {
            realm.delete(objects)
        }
    }
    
    func object<K>(for key: K) -> RealmObject? {
        let realm = try! Realm()
        return realm.object(ofType: RealmObject.self, forPrimaryKey: key)
    }
    
    /// Queries the db, if sent with no parameters gets all the realm object of type `RealmObject`.
    func get(_ predicateFormat: String? = nil, _ args: Any...) -> Results<RealmObject> {
        let realm = try! Realm()
        if let pf = predicateFormat {
            return realm.objects(RealmObject.self).filter(pf, args)
        } else {
            return realm.objects(RealmObject.self)
        }
    }
}

extension RealmObjectManager where RealmObject: RealmObjectProtocol, RealmObject == RealmObject.RealmObject {
    
    func update(_ objects: [RealmObject.ObjectType]) {
        self.update(objects.map { RealmObject.initialize(with: $0) })
    }
    
    func object<Key>(for key: Key) -> RealmObject.ObjectType? {
        let object: RealmObject? = self.object(for: key)
        return object?.asObject()
    }
    
    func allObjects() -> [RealmObject.ObjectType] {
        return self.get().map { $0.asObject() }
    }
}
