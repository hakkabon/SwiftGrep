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
    
    // MARK: - 3. Dynamic Substring Matching & Bounds
    
    func testBasicSubstringMatching() throws {
        // Pattern: "foo"
        let pattern = Regex.con(.symbol("f"), .con(.symbol("o"), .symbol("o")))
        let engine = RegexEngine(pattern)
        
        let input1 = "a foobar test"
        let match1 = try XCTUnwrap(engine.firstMatch(in: input1), "Engine should find 'foo' in the middle of a string")
        // Verify the highlighted bounds exactly cover the word "foo"
        XCTAssertEqual(String(input1[match1.range]), "foo")
        
        let input2 = "foo"
        let match2 = try XCTUnwrap(engine.firstMatch(in: input2))
        XCTAssertEqual(String(input2[match2.range]), "foo")
        
        XCTAssertNil(engine.firstMatch(in: "foboar"), "Engine should reject non-matching string")
    }
    
    func testAnyCharacterMatching() throws {
        // Pattern: "a.c"
        let pattern = Regex.con(.symbol("a"), .con(.any, .symbol("c")))
        let engine = RegexEngine(pattern)
        
        let input1 = "xyz abc test"
        let match1 = try XCTUnwrap(engine.firstMatch(in: input1))
        XCTAssertEqual(String(input1[match1.range]), "abc")
        
        let input2 = "aXc"
        let match2 = try XCTUnwrap(engine.firstMatch(in: input2))
        XCTAssertEqual(String(input2[match2.range]), "aXc")
        
        XCTAssertNil(engine.firstMatch(in: "ac"))
    }
    
    // MARK: - 4. Group Captures & Backreferences
    
    func testSimpleCaptureGroup() throws {
        // Pattern: [1: ba*]
        let aStar = Regex.star(.symbol("a"))
        let baStar = Regex.con(.symbol("b"), aStar)
        let pattern = Regex.capture(id: 1, baStar)
        
        let engine = RegexEngine(pattern)
        
        let input = "test baaaa string"
        let match = try XCTUnwrap(engine.firstMatch(in: input))
        
        // Assert matched bounds
        XCTAssertEqual(String(input[match.range]), "baaaa")
        // Assert exact capture dictionary
        XCTAssertEqual(match.captures[1], "baaaa", "Capture group 1 should capture 'baaaa'")
    }
    
    func testNestedCaptureGroups() throws {
        // Pattern: a[1:b[2:c]]
        let subcap = Regex.capture(id: 2, .symbol("c"))
        let cap = Regex.capture(id: 1, Regex.con(.symbol("b"), subcap))
        let pattern = Regex.con(.symbol("a"), cap)
        
        let engine = RegexEngine(pattern)
        let input = "xyzabc123"
        let match = try XCTUnwrap(engine.firstMatch(in: input))
        
        // Assert matched bounds
        XCTAssertEqual(String(input[match.range]), "abc")
        // Assert exact capture dictionaries (Fix applied here)
        XCTAssertEqual(match.captures[1], "bc", "Outer capture group 1 should capture 'bc'")
        XCTAssertEqual(match.captures[2], "c", "Inner capture group 2 should capture 'c'")
    }
    
    func testBackreferenceMatching() throws {
        // Pattern: [1:a|b]\1 (Matches "aa" or "bb", but not "ab" or "ba")
        let aOrB = Regex.alt([.symbol("a"), .symbol("b")])
        let capture = Regex.capture(id: 1, aOrB)
        let pattern = Regex.con(capture, .backreference(id: 1))
        
        let engine = RegexEngine(pattern)
        
        let input1 = "xxaayy"
        let match1 = try XCTUnwrap(engine.firstMatch(in: input1))
        XCTAssertEqual(String(input1[match1.range]), "aa", "Should match 'aa' as a substring")
        
        let input2 = "xxbbyy"
        let match2 = try XCTUnwrap(engine.firstMatch(in: input2))
        XCTAssertEqual(String(input2[match2.range]), "bb", "Should match 'bb' as a substring")
        
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
    
    // MARK: - Parser & Tokenizer Tests

    func testTokenizer() throws {
        let tokens = try Tokenizer.tokenize("a|b*\\1")
        let expected: [Token] = [.char("a"), .pipe, .char("b"), .star, .backref(1), .eof]
        XCTAssertEqual(tokens, expected)
    }

    func testParserComplex() throws {
        // Test that nesting creates correct captures
        let regex = try RegexParser.parse("(a(b))")
        // Should be capture(1: concat(a, capture(2: b)))
        XCTAssertEqual(regex.description, "[1:a[2:b]]")
    }

    // MARK: - Corner Case Matching

    func testEmptyMatch() throws {
        // The empty string regex ε should match the start of any line
        let engine = RegexEngine(.epsilon)
        let match = try XCTUnwrap(engine.firstMatch(in: "abc"))
        XCTAssertEqual(match.range.lowerBound, match.range.upperBound)
    }

    func testGreedyVsNonGreedy() throws {
        // Pattern a* should match "aaa" (longest) not "a"
        let engine = RegexEngine(.star(.symbol("a")))
        let match = try XCTUnwrap(engine.firstMatch(in: "aaa"))
        XCTAssertEqual(String("aaa"[match.range]), "aaa")
    }

    func testBackrefMismatch() {
        // [1:a|b]\1 : Match "ab" should fail
        let pattern = try! RegexParser.parse("([ab])\\1")
        let engine = RegexEngine(pattern)
        XCTAssertNil(engine.firstMatch(in: "ab"))
    }
}
