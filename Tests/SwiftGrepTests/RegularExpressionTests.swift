import XCTest
@testable import SwiftGrep

final class RegexAutomataTests: XCTestCase {

    // MARK: - 1. AST & Smart Constructors
    
    func testSmartConstructors() {
        let a = Regex.symbol("a")
        let b = Regex.symbol("b")
        let empty = Regex.empty
        let eps = Regex.epsilon
        
        // Concat Simplifications
        XCTAssertEqual(Regex.con(empty, a), .empty, "∅a should simplify to ∅")
        XCTAssertEqual(Regex.con(a, empty), .empty, "a∅ should simplify to ∅")
        XCTAssertEqual(Regex.con(eps, a), a, "εa should simplify to a")
        XCTAssertEqual(Regex.con(a, eps), a, "aε should simplify to a")
        
        // Alternation Simplifications
        XCTAssertEqual(Regex.alt([empty, a]), a, "a|∅ should simplify to a")
        XCTAssertEqual(Regex.alt([empty, empty]), .empty, "∅|∅ should simplify to ∅")
        
        // Nested Alternation Flattening
        let alt1 = Regex.alternation([a, b])
        let alt2 = Regex.alt([alt1, .symbol("c")])
        if case .alternation(let set) = alt2 {
            XCTAssertEqual(set.count, 3, "Nested alternations should flatten into a single set")
        } else {
            XCTFail("Expected flattened alternation")
        }
    }
    
    // MARK: - 2. Nullability
    
    func testNullability() {
        let emptyEnv: [Int: String] = [:]
        
        XCTAssertTrue(Regex.epsilon.isNullable(env: emptyEnv))
        XCTAssertFalse(Regex.empty.isNullable(env: emptyEnv))
        XCTAssertFalse(Regex.symbol("a").isNullable(env: emptyEnv))
        XCTAssertTrue(Regex.star(.symbol("a")).isNullable(env: emptyEnv))
        
        // Backreferences are nullable if their targeted environment string is empty or missing
        XCTAssertTrue(Regex.backreference(id: 1).isNullable(env: [:]))
        XCTAssertFalse(Regex.backreference(id: 1).isNullable(env: [1: "a"]))
    }
    
    // MARK: - 3. Dynamic Substring Matching
    
    func testBasicSubstringMatching() {
        // Pattern: "foo"
        let pattern = Regex.con(.symbol("f"), .con(.symbol("o"), .symbol("o")))
        let engine = RegexEngine(pattern)
        
        // Should match inside a larger string (Substring matching)
        XCTAssertNotNil(engine.firstMatch(in: "a foobar test"), "Engine should find 'foo' in the middle of a string")
        XCTAssertNotNil(engine.firstMatch(in: "foo"), "Engine should match exact string")
        XCTAssertNil(engine.firstMatch(in: "foboar"), "Engine should reject non-matching string")
    }
    
    func testAnyCharacterMatching() {
        // Pattern: "a.c"
        let pattern = Regex.con(.symbol("a"), .con(.any, .symbol("c")))
        let engine = RegexEngine(pattern)
        
        XCTAssertNotNil(engine.firstMatch(in: "abc"))
        XCTAssertNotNil(engine.firstMatch(in: "aXc"))
        XCTAssertNil(engine.firstMatch(in: "ac"))
    }
    
    // MARK: - 4. Group Captures & Backreferences
    
    func testSimpleCaptureGroup() {
        // Pattern: [1: ba*]
        let aStar = Regex.star(.symbol("a"))
        let baStar = Regex.con(.symbol("b"), aStar)
        let pattern = Regex.capture(id: 1, baStar)
        
        let engine = RegexEngine(pattern)
        let match = engine.firstMatch(in: "test baaaa string")
        
        XCTAssertNotNil(match)
        XCTAssertEqual(match?[1], "baaaa", "Capture group 1 should capture 'baaaa'")
    }
    
    func testNestedCaptureGroups() {
        // Pattern: a[1:b[2:c]]
        let subcap = Regex.capture(id: 2, .symbol("c"))
        let cap = Regex.capture(id: 1, Regex.con(.symbol("b"), subcap))
        let pattern = Regex.con(.symbol("a"), cap)
        
        let engine = RegexEngine(pattern)
        let match = engine.firstMatch(in: "xyzabc123")
        
        XCTAssertNotNil(match)
        XCTAssertEqual(match?[1], "bc", "Outer capture group 1 should capture 'bc'")
        XCTAssertEqual(match?[2], "c", "Inner capture group 2 should capture 'c'")
    }
    
    func testBackreferenceMatching() {
        // Pattern: [1:a|b]\1 (Matches "aa" or "bb", but not "ab" or "ba")
        let aOrB = Regex.alt([.symbol("a"), .symbol("b")])
        let capture = Regex.capture(id: 1, aOrB)
        let pattern = Regex.con(capture, .backreference(id: 1))
        
        let engine = RegexEngine(pattern)
        
        XCTAssertNotNil(engine.firstMatch(in: "xxaayy"), "Should match 'aa'")
        XCTAssertNotNil(engine.firstMatch(in: "xxbbyy"), "Should match 'bb'")
        XCTAssertNil(engine.firstMatch(in: "xxabyy"), "Should NOT match 'ab'")
        XCTAssertNil(engine.firstMatch(in: "xxbayy"), "Should NOT match 'ba'")
    }
    
    // MARK: - 5. Automata Construction & Brzozowski Minimization
    
    func testAntimirovNFAConstruction() {
        // Pattern: a(b|c)*
        let bOrC = Regex.alt([.symbol("b"), .symbol("c")])
        let pattern = Regex.con(.symbol("a"), .star(bOrC))
        
        let alphabet: Set<Character> = ["a", "b", "c"]
        let nfa = pattern.buildNFA(alphabet: alphabet)
        
        XCTAssertGreaterThan(nfa.states.count, 0, "NFA should contain states")
        XCTAssertGreaterThan(nfa.transitions.count, 0, "NFA should contain transitions")
        XCTAssertTrue(nfa.initialStates.contains(pattern), "Initial state should be the full AST")
    }
    
    func testBrzozowskiMinimization() {
        // Pattern: a*a* (Technically identical to a*, but AST implies redundancy)
        let aStar = Regex.star(.symbol("a"))
        let pattern = Regex.con(aStar, aStar)
        
        let alphabet: Set<Character> = ["a", "b"]
        
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let minimalDfa = nfa.minimized()
        
        // a* DFA with alphabet {a,b} should have exactly 2 states:
        // 1 accepting state (looping on 'a'), and 1 dead state (absorbing 'b')
        XCTAssertEqual(minimalDfa.states.count, 2, "Brzozowski minimization should reduce a*a* to an optimal 2-state DFA")
        
        // Assert Determinism: Each state should have exactly one target for each character in the alphabet
        for state in minimalDfa.states {
            for char in alphabet {
                let targets = minimalDfa.transitions[state]?[char] ?? []
                XCTAssertLessThanOrEqual(targets.count, 1, "Minimized automaton must be deterministic (DFA)")
            }
        }
    }
}
