//
//  DB.swift
//  Pods
//
//  Created by Gal Orlanczyk on 17/07/2017.
//
//

import Foundation

protocol DB_API {
    static var shared: DB { get }
    
    func update(item: DTGItem)
    func item(byId id: String) -> DTGItem
    func removeItem(byId: String)
    func getAllItems() -> [DTGItem]
    
    func set(tasks: [DownloadItemTask], onItemId id: String)
    func tasks(forItemId id: String) -> [DownloadItemTask]
    func removeTasks(fromItemId id: String)
}

extension DB_API {
    
    func items(byState state: DTGItemState) -> [DTGItem] {
        return self.getAllItems().filter { $0.state == state }
    }
}

class DB {
    
    /// The singleton shared db instance
    static let shared = DB()
    
    
}
