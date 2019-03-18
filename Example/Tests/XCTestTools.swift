//
//  XCTestTools.swift
//  DownloadToGo_Tests
//
//  Created by Noam Tamim on 17/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest


public func eq<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message, file: file, line: line)
}


