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

struct Queue<T> {
    
    /// The physical array that holds queue elements
    fileprivate var array = [T?]()
    /// The index of the first element
    fileprivate var head = 0
    /// The percentage of nil objects from array size to reorder queue elements (O(n) so it is better to only reorder only from some point)
    var queueOptimizationPercentage: Double
    /// The array minimum size to start reordering elements when certain percentage is met.
    var queueOptimizationMinimumSize: Int
    
    init(arrayOptimizationMinimumSize: Int = 50, arrayOptimizationPercentage: Double = 0.25) {
        self.queueOptimizationMinimumSize = arrayOptimizationMinimumSize
        self.queueOptimizationPercentage = arrayOptimizationPercentage
    }
    
    var isEmpty: Bool {
        return self.count == 0
    }
    
    var count: Int {
        return self.array.count - self.head
    }
    
    mutating func enqueue(_ element: T) {
        self.array.append(element)
    }
    
    mutating func enqueue(_ elements: [T]) {
        self.array.append(contentsOf: elements as [T?])
    }
    
    mutating func enqueueAtHead(_ element: T) {
        self.array.insert(element, at: self.head)
    }
    
    mutating func enqueueAtHead(_ elements: [T]) {
        self.array.insert(contentsOf: elements as [T?], at: head)
    }
    
    mutating func dequeue() -> T? {
        guard self.head < self.array.count, let element = self.array[head] else { return nil }
        
        self.array[self.head] = nil
        self.head += 1
        
        let percentage = Double(self.head)/Double(self.array.count)
        if self.array.count > self.queueOptimizationMinimumSize && percentage > self.queueOptimizationPercentage {
            self.array.removeFirst(self.head)
            self.head = 0
        }
        
        return element
    }
    
    /// clears the queue of all items (like remove all)
    mutating func purge() {
        self.array.removeAll()
    }
}
