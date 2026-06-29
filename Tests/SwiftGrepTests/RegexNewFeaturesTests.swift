//
//  RegexNewFeaturesTests.swift
//  SwiftGrepTests
//

import XCTest
@testable import SwiftGrep

final class RegexNewFeaturesTests: XCTestCase {

    // MARK: - 1. Tokenizer Tests

    func testNewTokens() throws {
        let tokens = try Tokenizer.tokenize("[a-c]+?")
        let expected: [Token] = [
            .lBracket, .char("a"), .char("-"), .char("c"), .rBracket,
            .plus, .question, .eof
        ]
        XCTAssertEqual(tokens, expected)
    }

    // MARK: - 2. Parser Tests

    func testPlusParser() throws {
        let ast = try RegexParser.parse("a+")
        XCTAssertEqual(ast.description, "(a)+")
    }

    func testQuestionParser() throws {
        let ast = try RegexParser.parse("a?")
        XCTAssertEqual(ast.description, "(a)?")
    }

    func testSimpleCharacterClassParser() throws {
        let ast = try RegexParser.parse("[abc]")
        // AST descriptions sorted components alphabetically
        XCTAssertEqual(ast.description, "[abc]")
    }

    func testNegatedCharacterClassParser() throws {
        let ast = try RegexParser.parse("[^abc]")
        XCTAssertEqual(ast.description, "[^abc]")
    }

    func testRangeCharacterClassParser() throws {
        let ast = try RegexParser.parse("[a-c]")
        XCTAssertEqual(ast.description, "[a-c]")
    }

    func testMixedCharacterClassParser() throws {
        let ast = try RegexParser.parse("[a-cx-z0-9]")
        XCTAssertEqual(ast.description, "[0-9a-cx-z]")
    }

    func testTrailingDashCharacterClassParser() throws {
        let ast = try RegexParser.parse("[a-c-]")
        XCTAssertEqual(ast.description, "[-a-c]")
    }

    func testLeadingDashCharacterClassParser() throws {
        let ast = try RegexParser.parse("[-a-c]")
        XCTAssertEqual(ast.description, "[-a-c]")
    }

    func testInvalidRangeThrows() {
        XCTAssertThrowsError(try RegexParser.parse("[z-a]"))
    }

    func testMissingClosingBracketThrows() {
        XCTAssertThrowsError(try RegexParser.parse("[a-z")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected ParseError")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Missing closing bracket ']'")
        }
    }

    // MARK: - 3. RegexEngine Matching Tests

    func testPlusMatching() throws {
        let pattern = try RegexParser.parse("a+")
        let engine = RegexEngine(pattern)

        let match1 = try XCTUnwrap(engine.firstMatch(in: "aa"))
        XCTAssertEqual(String("aa"[match1.range]), "aa")

        let match2 = try XCTUnwrap(engine.firstMatch(in: "xay"))
        XCTAssertEqual(String("xay"[match2.range]), "a")

        XCTAssertNil(engine.firstMatch(in: "xyz"))
    }

    func testQuestionMatching() throws {
        let pattern = try RegexParser.parse("ab?c")
        let engine = RegexEngine(pattern)

        let match1 = try XCTUnwrap(engine.firstMatch(in: "abc"))
        XCTAssertEqual(String("abc"[match1.range]), "abc")

        let match2 = try XCTUnwrap(engine.firstMatch(in: "ac"))
        XCTAssertEqual(String("ac"[match2.range]), "ac")

        XCTAssertNil(engine.firstMatch(in: "abbc"))
    }

    func testCharacterClassMatching() throws {
        let pattern = try RegexParser.parse("[a-z]+")
        let engine = RegexEngine(pattern)

        let match1 = try XCTUnwrap(engine.firstMatch(in: "123abc456"))
        XCTAssertEqual(String("123abc456"[match1.range]), "abc")

        XCTAssertNil(engine.firstMatch(in: "123456"))
    }

    func testNegatedCharacterClassMatching() throws {
        let pattern = try RegexParser.parse("[^0-9]+")
        let engine = RegexEngine(pattern)

        let match1 = try XCTUnwrap(engine.firstMatch(in: "12abc34"))
        XCTAssertEqual(String("12abc34"[match1.range]), "abc")
    }

    // MARK: - 4. Automata & Minimization Integration

    func testAutomatonWithCharacterClass() throws {
        let pattern = try RegexParser.parse("[a-c]")
        let alphabet: Set<Character> = ["a", "b", "c", "d"]
        let nfa = pattern.buildNFA(alphabet: alphabet)
        let minimalDfa = nfa.minimized()

        XCTAssertEqual(minimalDfa.states.count, 2) // 2 states: 1 initial state, 1 accepting state for matching a, b, or c
    }
}
