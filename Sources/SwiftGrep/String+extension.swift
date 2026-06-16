//
//  String+extension.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

// Standard ANSI Terminal Color Codes
let ANSI_RED = "\u{001B}[31;1m" // Bold Red
let ANSI_RESET = "\u{001B}[0m"

extension String {

    /// Inserts ANSI escape codes around the given range to highlight it in the terminal.
    public func highlighted(in range: Range<String.Index>) -> String {
        var result = self
        // Insert backwards to preserve string index validity
        result.insert(contentsOf: ANSI_RESET, at: range.upperBound)
        result.insert(contentsOf: ANSI_RED, at: range.lowerBound)
        return result
    }
}
