//
//  RealmObjectProtocol.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation
import RealmSwift

protocol RealmObjectProtocol: class {
    associatedtype RealmObject: Object
    associatedtype ObjectType
    
    /// used to create an object from realm object
    func asObject() -> ObjectType
    /// used to create realm object from object
    static func initialize(with object: ObjectType) -> RealmObject
}
