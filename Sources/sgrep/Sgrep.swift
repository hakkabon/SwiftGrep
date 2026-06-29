//
//  Sgrep.swift
//  sgrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import ArgumentParser
import SwiftGrep

@main
struct SwiftGrep: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sgrep",
        abstract: "A theoretical FSA-based grep tool written in Swift."
    )

    @Argument(help: "The regular expression pattern.")
    var pattern: String

    @Argument(help: "The files to search. If empty, reads from standard input.")
    var files: [String] = []

    @Flag(name: .shortAndLong, help: "Prefix each line of output with the 1-based line number.")
    var lineNumber: Bool = false
    
    @Flag(name: [.long, .customShort("H")], help: "Highlight matched text. Name of short option being '-H' (capital H).")
    var highlight: Bool = false

    @Flag(name: .shortAndLong, help: "Invert the sense of matching, to select non-matching lines.")
    var invertMatch: Bool = false

    mutating func run() async throws {
        // Parse the string pattern into your AST
        let ast = try RegexParser.parse(pattern)
        
        // Initialize your NFA / Matching Engine
        let engine = RegexEngine(ast)

        // Process Streams
        if files.isEmpty {
            // Read from standard input (e.g., `cat log.txt | sgrep "error"`)
            var currentLineNumber = 1
            var iterator = FileHandle.standardInput.bytes.lines.makeAsyncIterator()
            
            while let line = try await iterator.next() {
                let matched = engine.hasMatch(in: line)
                if matched != invertMatch {
                    let prefix = lineNumber ? "\(currentLineNumber):" : ""
                    if highlight, !invertMatch, let result = engine.firstMatch(in: line) {
                        print("\(prefix)\(line.highlighted(in: result.range))")
                    } else {
                        print("\(prefix)\(line)")
                    }
                }
                currentLineNumber += 1
            }
        } else {
            // Read from specified files
            for file in files {
                let fileURL = URL(fileURLWithPath: file)
                do {
                    try await processFile(url: fileURL, engine: engine, showLineNumbers: lineNumber, highlight: highlight, invertMatch: invertMatch)
                } catch {
                    FileHandle.standardError.write("sgrep: \(file): No such file or directory\n".data(using: .utf8)!)
                }
            }
        }
    }
}
