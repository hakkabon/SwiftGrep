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

/*
// Target: Regex to find "a" followed by nested capture of "bc", followed by backref \1
// Pattern: a(b(c))\2
let subcap = Regex.capture(id: 2, .symbol("c"))
let cap = Regex.capture(id: 1, .concat(.symbol("b"), subcap))
let p1 = Regex.concat(.symbol("a"), cap)
let pattern = Regex.concat(p1, .backreference(id: 2)) // Expects "c" again

// 1. Dynamic Matching (Captures & Substrings Engine)
let engine = RegexEngine(pattern)
if let env = engine.firstMatch(in: "xyzabcctest") {
    print("Match found! Captures: \(env)")
    // Output: Match found! Captures: [1: "bc", 2: "c"]
}

// 2. Formal Automata Generator & Minimization (Brzozowski)
// We isolate a purely regular form for static NFA generation
let regularPattern = Regex.concat(.symbol("a"), .star(.symbol("b")))
let nfa = regularPattern.buildNFA(alphabet: ["a", "b"])
let minimalDfa = nfa.minimized()

print("Original Antimirov NFA States: \(nfa.states.count)")
print("Minimized DFA States: \(minimalDfa.states.count)")

*/


