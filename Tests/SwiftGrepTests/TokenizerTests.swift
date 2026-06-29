//
//  TokenizerTests.swift
//  SwiftGrepTests
//
//  Comprehensive coverage of `Tokenizer`, including escape handling and the
//  single-digit backreference limitation documented in README.md.
//

import XCTest
@testable import SwiftGrep

final class TokenizerTests: XCTestCase {

    // MARK: - Basics

    func testEmptyInputProducesOnlyEOF() throws {
        let tokens = try Tokenizer.tokenize("")
        XCTAssertEqual(tokens, [.eof])
    }

    func testPlainLiteralCharacters() throws {
        let tokens = try Tokenizer.tokenize("abc")
        XCTAssertEqual(tokens, [.char("a"), .char("b"), .char("c"), .eof])
    }

    func testMetaCharacterTokens() throws {
        // '.', '|', '*', '(', ')' all carry special meaning when unescaped.
        let tokens = try Tokenizer.tokenize(".|*()")
        XCTAssertEqual(tokens, [.dot, .pipe, .star, .lParen, .rParen, .eof])
    }

    func testMixedLiteralsAndOperators() throws {
        // "(a.b)*\2"
        let tokens = try Tokenizer.tokenize("(a.b)*\\2")
        XCTAssertEqual(tokens, [
            .lParen, .char("a"), .dot, .char("b"), .rParen, .star, .backref(2), .eof,
        ])
    }

    // MARK: - Escaping

    func testEscapedMetaCharactersBecomeLiterals() throws {
        // Each escaped metacharacter should yield a plain .char token, not its
        // special-meaning token.
        let tokens = try Tokenizer.tokenize("\\.\\|\\*\\(\\)")
        XCTAssertEqual(tokens, [
            .char("."), .char("|"), .char("*"), .char("("), .char(")"), .eof,
        ])
    }

    func testEscapedBackslashIsALiteralBackslash() throws {
        let tokens = try Tokenizer.tokenize("\\\\")
        XCTAssertEqual(tokens, [.char("\\"), .eof])
    }

    func testEscapedLetterHasNoSpecialMeaning() throws {
        // This engine has no \d / \w / \s style shorthands: an escaped letter
        // is just that letter, literally.
        let tokens = try Tokenizer.tokenize("\\d")
        XCTAssertEqual(tokens, [.char("d"), .eof])
    }

    func testTrailingBackslashThrows() {
        XCTAssertThrowsError(try Tokenizer.tokenize("a\\")) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected a ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.description, "Parse Error: Invalid escape sequence")
        }
    }

    // MARK: - Backreferences

    func testSingleDigitBackreferences() throws {
        let tokens = try Tokenizer.tokenize("\\1\\9")
        XCTAssertEqual(tokens, [.backref(1), .backref(9), .eof])
    }

    func testEscapedZeroIsALiteralDigitNotABackreference() throws {
        // `\0` has no digit > 0, so it falls through to a literal '0' character.
        let tokens = try Tokenizer.tokenize("\\0")
        XCTAssertEqual(tokens, [.char("0"), .eof])
    }

    func testMultiDigitBackreferenceIsNotSupported() throws {
        // Only the single digit immediately after '\' is consumed as a backreference
        // id; any further digits are tokenized as ordinary literal characters.
        // "\12" therefore becomes backreference(1) followed by a literal '2', not
        // "backreference 12". This is a known limitation, documented in README.md.
        let tokens = try Tokenizer.tokenize("\\12")
        XCTAssertEqual(tokens, [.backref(1), .char("2"), .eof])
    }

    // MARK: - Documenting the new character-class support
 
    func testBracketsAreTokenizedAsBrackets() throws {
        // Now that `SwiftGrep` supports character classes, '[' and ']' are
        // tokenized as .lBracket and .rBracket.
        let tokens = try Tokenizer.tokenize("[ab]")
        XCTAssertEqual(tokens, [.lBracket, .char("a"), .char("b"), .rBracket, .eof])
    }
 
    // MARK: - Token.description
 
    func testTokenDescriptions() {
        XCTAssertEqual(Token.eof.description, "EOF")
        XCTAssertEqual(Token.dot.description, ".")
        XCTAssertEqual(Token.pipe.description, "|")
        XCTAssertEqual(Token.star.description, "*")
        XCTAssertEqual(Token.plus.description, "+")
        XCTAssertEqual(Token.question.description, "?")
        XCTAssertEqual(Token.lParen.description, "(")
        XCTAssertEqual(Token.rParen.description, ")")
        XCTAssertEqual(Token.lBracket.description, "[")
        XCTAssertEqual(Token.rBracket.description, "]")
        XCTAssertEqual(Token.char("x").description, "x")
        XCTAssertEqual(Token.backref(3).description, "\\3")
    }
}
