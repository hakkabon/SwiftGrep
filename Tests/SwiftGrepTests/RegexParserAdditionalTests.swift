//
//  RegexParserAdditionalTests.swift
//  SwiftGrepTests
//
//  Additional coverage for `RegexParser`: operator precedence, smart-constructor
//  interaction with the parser, capture-group numbering, and error paths. These
//  complement the single happy-path case in RegexParserTests.swift.
//

import XCTest
@testable import SwiftGrep

final class RegexParserAdditionalTests: XCTestCase {

    // MARK: - Operator precedence

    func testStarBindsTighterThanConcatenation() throws {
        // "ab*" means a(b*), not (ab)*.
        let ast = try RegexParser.parse("ab*")
        XCTAssertEqual(ast.description, "a(b)*")
    }

    func testConcatenationBindsTighterThanAlternation() throws {
        // "ab|cd" means (ab)|(cd), not a(b|c)d.
        let ast = try RegexParser.parse("ab|cd")
        XCTAssertEqual(ast.description, "(ab|cd)")
    }

    func testRepeatedStarsNestRatherThanCollapse() throws {
        // "a**" is parsed as star(star(a)) -- harmless but not simplified away.
        let ast = try RegexParser.parse("a**")
        XCTAssertEqual(ast.description, "((a)*)*")
    }

    // MARK: - Smart-constructor interaction with parsed alternations

    func testIdenticalAlternativesCollapseToASingleNode() throws {
        // Regex.alt de-duplicates structurally-equal branches via Set, and a
        // singleton alternation collapses to its one member with no "(...)" wrapper.
        let ast = try RegexParser.parse("a|a")
        XCTAssertEqual(ast.description, "a")
    }

    func testDuplicateAlternativesAreDedupedButDistinctOnesSurvive() throws {
        let ast = try RegexParser.parse("a|b|a")
        XCTAssertEqual(ast.description, "(a|b)")
    }

    func testEmptyGroupParsesAsCaptureOfEpsilon() throws {
        let ast = try RegexParser.parse("()")
        XCTAssertEqual(ast.description, "[1:ε]")
    }

    func testTrailingAlternationBranchBecomesEpsilon() throws {
        // "a|" -- the parser's own comments describe this exact case.
        let ast = try RegexParser.parse("a|")
        XCTAssertEqual(ast.description, "(a|ε)")
    }

    func testLeadingAlternationBranchBecomesEpsilon() throws {
        let ast = try RegexParser.parse("|a")
        XCTAssertEqual(ast.description, "(a|ε)")
    }

    // MARK: - Capture-group numbering

    func testCaptureGroupsAreNumberedLeftToRightByOpeningParen() throws {
        // Group numbering follows the order '(' tokens are *encountered*, not
        // nesting depth: the inner "(b)" opens before the outer "(c)", so it gets
        // the lower id even though it's nested one level deeper.
        let ast = try RegexParser.parse("(a(b))(c)")
        XCTAssertEqual(ast.description, "[1:a[2:b]][3:c]")
    }

    // MARK: - Multi-digit backreferences (parser-level confirmation of the
    // tokenizer-level limitation documented in TokenizerTests)

    func testMultiDigitBackreferenceParsesAsBackrefPlusLiteralDigit() throws {
        let ast = try RegexParser.parse("(a)\\12")
        XCTAssertEqual(ast.description, "[1:a]\\12")
    }

    // MARK: - Error paths

    func testMissingClosingParenThrows() {
        XCTAssertThrowsError(try RegexParser.parse("(a")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected a ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Missing closing parenthesis ')'")
        }
    }

    func testLeadingStarWithNothingToRepeatThrows() {
        XCTAssertThrowsError(try RegexParser.parse("*a")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected a ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Quantifier '*' requires a preceding element")
        }
    }

    func testStarAfterGroupWithNothingToRepeatThrows() {
        // The same rule applies after a closing paren: "(a)**" is fine (two stars
        // chain onto the group), but a star with nothing at all before it is not.
        XCTAssertThrowsError(try RegexParser.parse("(a)|*b")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected a ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Quantifier '*' requires a preceding element")
        }
    }

    func testUnexpectedTrailingTokenThrows() {
        // A stray ')' with no matching '(' is left over once the top-level
        // alternation/concat rules have consumed everything they can, and the
        // root rule's EOF check rejects it.
        XCTAssertThrowsError(try RegexParser.parse("a)")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected a ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Unexpected token ')'")
        }
    }

    // MARK: - Dangling / forward backreferences are accepted by the parser

    func testForwardBackreferenceIsAcceptedByTheParser() throws {
        // Unlike many PCRE-style engines, this parser does not statically reject a
        // backreference to a capture group that hasn't been opened yet. Whether it
        // *matches* anything sensible is a separate, semantic question -- see
        // MatchingCornerCaseTests.testForwardBackreferenceIsTreatedAsVacuouslyNullable.
        let ast = try RegexParser.parse("\\1(a)")
        XCTAssertEqual(ast.description, "\\1[1:a]")
    }
}
