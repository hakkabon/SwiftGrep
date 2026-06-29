//
//  FileIO.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import SwiftGrep

extension RegexEngine {
    /// Evaluates if a pattern exists anywhere in a given line
    public func hasMatch(in line: String) -> Bool {
        return self.firstMatch(in: line) != nil
    }
}

func processFile(url: URL, engine: RegexEngine, showLineNumbers: Bool, highlight: Bool, invertMatch: Bool) async throws {
    var lineNumber = 1
    // Asynchronously reads the file line-by-line with minimal memory footprint
    for try await line in url.lines {
        let matched = engine.hasMatch(in: line)
        if matched != invertMatch {
            let prefix = showLineNumbers ? "\(lineNumber):" : ""
            if highlight, !invertMatch, let result = engine.firstMatch(in: line) {
                print("\(prefix)\(line.highlighted(in: result.range))")
            } else {
                print("\(prefix)\(line)")
            }
        }
        lineNumber += 1
    }
}
