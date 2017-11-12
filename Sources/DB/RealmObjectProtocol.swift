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

protocol RealmCascadeDeleteable {
    associatedtype RealmObject: Object
    func cascadeDelete(_ objects: [RealmObject]) throws
}

protocol PrimaryKeyable {
    associatedtype KeyType
    var pk: KeyType { get }
}

protocol RealmObjectProtocol {
    associatedtype RealmObject: Object
    associatedtype ObjectType
    
    /// used to create an object from realm object
    func asObject() -> ObjectType
    /// used to create realm object from object
    static func initialize(with object: ObjectType) -> RealmObject
}
