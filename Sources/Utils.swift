//
//  Utils.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 27/12/2018.
//

import Foundation

extension RandomAccessCollection {
    
    /// - Parameter areInIncreasingOrder: return nil when two element are equal
    /// - Returns: the sorted collection
    public func stableSorted(by areInIncreasingOrder: (Iterator.Element, Iterator.Element) -> Bool?) -> [Iterator.Element] {
        
        let sorted = self.enumerated().sorted { (one, another) -> Bool in
            if let result = areInIncreasingOrder(one.element, another.element) {
                return result
            } else {
                return one.offset < another.offset
            }
        }
        return sorted.map{ $0.element }
    }
}
