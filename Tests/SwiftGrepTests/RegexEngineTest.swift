import Testing
@testable import SwiftGrep

@Test()
func testExample() async throws {
    let pattern = Regex.con(.symbol("e"), .star(.symbol("r"))) // Matches "e", "er", "err", etc.
    let engine = RegexEngine(pattern)

    let lines = [
        "No errors found during compilation.",
        "Warning: unhandled exception.",
        "System perfectly operational."
    ]

    for line in lines {
        if let match = engine.firstMatch(in: line) {
            // Output with Terminal colors!
            let visualLine = line.highlighted(in: match.range)
            print(visualLine)
            
            // Optional: show exact capture boundaries or offsets
            // print("Matched: '\(line[match.range])'")
        }
    }
}

