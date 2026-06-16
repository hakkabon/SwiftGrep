//
//  Example.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//


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
