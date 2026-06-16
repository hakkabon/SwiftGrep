//
//  RegexParser.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

public class RegexParser {

    public init() {}

    public func parse(_ input: String) throws -> Regex {
        // A standard recursive descent parser would go here.
        // It reads tokens, handles operator precedence (* is higher than concat,
        // concat is higher than |), and returns your `Regex` enum.
        return .empty
        
        
        // Example handling of escaping: "\1" -> .backreference(1)
        // Example handling of groups: "(...)" -> .capture(...)
        // fatalError("Requires a Lexer/Parser implementation")
    }
}
