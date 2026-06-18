//
//  AutomatonTests.swift
//  SwiftGrepTests
//
//  Rather than hand-counting expected state numbers (which is what the existing
//  Brzozowski test in RegularExpressionTests.swift does for a*a*), these tests
//  check *language equivalence*: a generic simulator replays an automaton -- NFA,
//  determinized DFA, or doubly-determinized minimal DFA alike -- against a list of
//  strings, and we assert the answer doesn't change across `buildNFA`,
//  `determinized()`, and `minimized()`. We also check the textbook
//  reversal-recognizes-the-reverse-language theorem for `reversed()`.
//

import XCTest
@testable import SwiftGrep

/// Generic subset-of-states simulator. Works unchanged for a nondeterministic
/// `Automaton<Regex>`, a determinized `Automaton<Set<Regex>>`, or a doubly-
/// determinized `Automaton<Set<Set<Regex>>>` -- the algorithm doesn't care
/// whether the per-character transition sets happen to contain 0, 1, or many
/// elements.
private func accepts<State: Hashable>(_ automaton: Automaton<State>, _ input: String) -> Bool {
    var current = automaton.initialStates
    for ch in input {
        var next: Set<State> = []
        for state in current {
            if let targets = automaton.transitions[state]?[ch] {
                next.formUnion(targets)
            }
        }
        current = next
        if current.isEmpty { return false }
    }
    return !current.isDisjoint(with: automaton.acceptingStates)
}

/// True iff every state has at most one outgoing transition per alphabet symbol.
private func isDeterministic<State: Hashable>(_ automaton: Automaton<State>) -> Bool {
    for state in automaton.states {
        for char in automaton.alphabet {
            if (automaton.transitions[state]?[char] ?? []).count > 1 {
                return false
            }
        }
    }
    return true
}

final class AutomatonTests: XCTestCase {

    // Pattern: a(b|c)* -- "a" followed by any number of b's and c's in any order.
    private func aBOrCStarFixture() -> (pattern: Regex, alphabet: Set<Character>) {
        let bOrC = Regex.alt([.symbol("b"), .symbol("c")])
        let pattern = Regex.con(.symbol("a"), .star(bOrC))
        return (pattern, ["a", "b", "c"])
    }

    private let aBOrCStarTestCases: [(String, Bool)] = [
        ("", false),
        ("a", true),
        ("b", false),
        ("ab", true),
        ("ac", true),
        ("abc", true),
        ("acb", true),
        ("acbcbcb", true),
        ("aa", false),
        ("abca", false),
        ("ba", false),
    ]

    func testBuildNFARecognizesExpectedLanguage() {
        let (pattern, alphabet) = aBOrCStarFixture()
        let nfa = pattern.buildNFA(alphabet: alphabet)

        for (input, expected) in aBOrCStarTestCases {
            XCTAssertEqual(accepts(nfa, input), expected, "NFA membership mismatch for \"\(input)\"")
        }
    }

    func testDeterminizedIsDeterministicAndPreservesLanguage() {
        let (pattern, alphabet) = aBOrCStarFixture()
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let dfa = nfa.determinized()

        XCTAssertTrue(isDeterministic(dfa), "Powerset construction must yield at most one target per (state, symbol)")
        for (input, expected) in aBOrCStarTestCases {
            XCTAssertEqual(accepts(dfa, input), expected, "Determinized DFA membership mismatch for \"\(input)\"")
        }
    }

    func testMinimizedIsDeterministicAndPreservesLanguage() {
        let (pattern, alphabet) = aBOrCStarFixture()
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let minimalDfa = nfa.minimized()

        XCTAssertTrue(isDeterministic(minimalDfa), "Brzozowski-minimized automaton must be a true DFA")
        XCTAssertFalse(minimalDfa.states.isEmpty)
        for (input, expected) in aBOrCStarTestCases {
            XCTAssertEqual(accepts(minimalDfa, input), expected, "Minimized DFA membership mismatch for \"\(input)\"")
        }
    }

    // MARK: - reversed()

    func testReversedRecognizesTheReverseLanguage() {
        // Pattern: ab|cd -- the (tiny, finite) language {"ab", "cd"}.
        let pattern = Regex.alt([
            Regex.con(.symbol("a"), .symbol("b")),
            Regex.con(.symbol("c"), .symbol("d")),
        ])
        let alphabet: Set<Character> = ["a", "b", "c", "d"]
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let reversedNfa = nfa.reversed()

        let testCases = ["ab", "cd", "a", "ac", "ba", "dcx", ""]
        for s in testCases {
            let forward = accepts(nfa, s)
            let reversedOfReversedInput = accepts(reversedNfa, String(s.reversed()))
            XCTAssertEqual(
                forward, reversedOfReversedInput,
                "reversed() must recognize exactly the reverse language: accepts(A, s) should equal accepts(reversed(A), reverse(s)) for \"\(s)\""
            )
        }
    }

    func testReversingTwiceRecoversTheOriginalLanguage() {
        let (pattern, alphabet) = aBOrCStarFixture()
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let roundTripped = nfa.reversed().reversed()

        for (input, expected) in aBOrCStarTestCases {
            XCTAssertEqual(accepts(roundTripped, input), expected, "reversed().reversed() must recognize the original language for \"\(input)\"")
        }
    }
}
