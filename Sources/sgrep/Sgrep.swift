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
    
    @Flag(name: .shortAndLong, help: "Invert the sense of matching, to select non-matching lines.")
    var invertMatch: Bool = false

    mutating func run() async throws {
        // 1. Parse the string pattern into your AST
        let ast = try RegexParser().parse(pattern)
        
        // 2. Initialize your NFA / Matching Engine
        let engine = RegexEngine(ast)

        // 3. Process Streams
        if files.isEmpty {
            // Read from standard input (e.g., `cat log.txt | sgrep "error"`)
            var currentLineNumber = 1
            var iterator = FileHandle.standardInput.bytes.lines.makeAsyncIterator()
            
            while let line = try await iterator.next() {
                let matched = engine.hasMatch(in: line)
                if matched != invertMatch { // XOR logic for invert match flag
                    let prefix = lineNumber ? "\(currentLineNumber):" : ""
                    print("\(prefix)\(line)")
                }
                currentLineNumber += 1
            }
        } else {
            // Read from specified files
            for file in files {
                let fileURL = URL(fileURLWithPath: file)
                do {
                    try await processFile(url: fileURL, engine: engine, showLineNumbers: lineNumber)
                } catch {
                    FileHandle.standardError.write("sgrep: \(file): No such file or directory\n".data(using: .utf8)!)
                }
            }
        }
    }
}
