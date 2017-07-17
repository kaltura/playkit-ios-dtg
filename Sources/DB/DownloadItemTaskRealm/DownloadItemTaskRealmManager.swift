//
//  DownloadItemTaskRealmManager.swift
//  Pods
//
//  Created by Gal Orlanczyk on 16/07/2017.
//
//

import Foundation

class DownloadItemTaskRealmManager: RealmObjectManager {
    typealias RealmObject = DownloadItemTaskRealm
    
    func allTasks() -> [DownloadItemTask] {
        return self.get().map { $0.asObject() }
    }
}
