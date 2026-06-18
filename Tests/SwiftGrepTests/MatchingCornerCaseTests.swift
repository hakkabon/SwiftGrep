//
//  MatchingCornerCaseTests.swift
//  SwiftGrepTests
//
//  Targeted corner cases for `RegexEngine`: true POSIX leftmost-longest semantics
//  (as opposed to "first alternative that matches," which is what backtracking
//  engines typically give you), the engine's actual (accumulating) repeated-capture
//  semantics, forward/dangling backreferences, and robustness against the classic
//  "(a*)*b"-shaped ReDoS pattern that defeats naive backtracking engines.
//

import XCTest
@testable import SwiftGrep

final class MatchingCornerCaseTests: XCTestCase {

    // MARK: - Leftmost-longest semantics

    func testLongestAlternativeWinsAtTheSameStartPosition() throws {
        // Pattern: a|ab. POSIX leftmost-longest semantics say that among all
        // matches starting at the same (leftmost) position, the longest one wins
        // -- this is *not* "whichever alternative was listed/tried first."
        let pattern = Regex.alt([.symbol("a"), Regex.con(.symbol("a"), .symbol("b"))])
        let engine = RegexEngine(pattern)

        let match = try XCTUnwrap(engine.firstMatch(in: "ab"))
        XCTAssertEqual(String("ab"[match.range]), "ab", "The longer alternative should win when both start at index 0")
    }

    func testLeftmostStartStrictlyOutranksALongerLaterMatch() throws {
        // Pattern: a|bb. A match starting earlier always wins over a match that
        // starts later, even if the later match is longer. This is the defining
        // property of "leftmost"-longest, as opposed to simply "longest anywhere."
        let pattern = Regex.alt([.symbol("a"), Regex.con(.symbol("b"), .symbol("b"))])
        let engine = RegexEngine(pattern)

        let match = try XCTUnwrap(engine.firstMatch(in: "abb"))
        XCTAssertEqual(String("abb"[match.range]), "a", "A shorter match starting at index 0 must beat a longer match starting at index 1")
    }

    // MARK: - Repeated capture groups: documenting this engine's actual semantics

    func testRepeatedCaptureGroupAccumulatesAcrossIterations() throws {
        // For (a)* against "aaa", this engine's capture environment accumulates the
        // text consumed on *every* iteration of the star, rather than retaining
        // only the most recent iteration the way PCRE/Perl do. PCRE would report
        // captures[1] == "a" here; this engine reports "aaa". This is a deliberate
        // consequence of how `derivative(with:env:)` threads its capture set
        // through `.star`, not a bug -- see ALGORITHMS.md / README.md.
        let pattern = try RegexParser.parse("(a)*")
        let engine = RegexEngine(pattern)

        let match = try XCTUnwrap(engine.firstMatch(in: "aaa"))
        XCTAssertEqual(String("aaa"[match.range]), "aaa")
        XCTAssertEqual(match.captures[1], "aaa")
    }

    // MARK: - Forward / dangling backreferences

    func testForwardBackreferenceIsTreatedAsVacuouslyNullable() throws {
        // `\1(a)` references group 1 before it has ever captured anything. Because
        // an unset capture is considered nullable (isNullable returns true when
        // env[id] is nil), the leading `\1` is simply skipped the first time
        // through, and the pattern behaves as if it were just `(a)`. Many
        // PCRE-style engines instead reject this pattern statically, or always
        // fail an unmatched backreference -- this is a deliberate, documented
        // difference in semantics, not an oversight.
        let pattern = try RegexParser.parse("\\1(a)")
        let engine = RegexEngine(pattern)

        let match = try XCTUnwrap(engine.firstMatch(in: "a"))
        XCTAssertEqual(String("a"[match.range]), "a")
        XCTAssertEqual(match.captures[1], "a")
    }

    func testChainedIndependentCapturesAndBackreferences() throws {
        // "(a)(b)\1\2" requires the literal sequence "a", then "b", then a repeat
        // of group 1's content ("a"), then a repeat of group 2's content ("b") --
        // i.e. it matches exactly "abab", with two independent capture/backreference
        // pairs chained together rather than nested.
        let pattern = try RegexParser.parse("(a)(b)\\1\\2")
        let engine = RegexEngine(pattern)

        let match = try XCTUnwrap(engine.firstMatch(in: "xyzabab123"))
        XCTAssertEqual(String("xyzabab123"[match.range]), "abab")
        XCTAssertEqual(match.captures[1], "a")
        XCTAssertEqual(match.captures[2], "b")

        XCTAssertNil(engine.firstMatch(in: "xyzabba123"), "\"abba\" must not match -- the second half doesn't echo the captures correctly")
    }

    // MARK: - `.` (any character)

    func testDotRequiresExactlyOneCharacterAndNeverMatchesEmptyInput() throws {
        let engine = RegexEngine(.any)
        XCTAssertNil(engine.firstMatch(in: ""), "`.` is not nullable -- it must consume exactly one character")

        let match = try XCTUnwrap(engine.firstMatch(in: "x"))
        XCTAssertEqual(String("x"[match.range]), "x")
    }

    // MARK: - Robustness against classically catastrophic backtracking shapes

    func testNestedStarPatternDoesNotHangOnLongNonMatchingInput() throws {
        // "(a*)*b" is a textbook ReDoS pattern shape for backtracking engines: on a
        // long run of 'a' characters with no trailing 'b', a backtracking VM must
        // explore an exponential number of ways to partition the 'a's between the
        // inner and outer stars before giving up. Because this engine explores all
        // of those "partitions" simultaneously as parallel automaton states rather
        // than serially via backtracking, it should reject the input quickly rather
        // than hang.
        let pattern = try RegexParser.parse("(a*)*b")
        let engine = RegexEngine(pattern)

        let longRunOfAs = String(repeating: "a", count: 300)
        XCTAssertNil(engine.firstMatch(in: longRunOfAs), "There is no 'b' anywhere in the input, so this must not match")
    }

    func testNestedStarPatternStillMatchesWhenTrailingCharacterIsPresent() throws {
        let pattern = try RegexParser.parse("(a*)*b")
        let engine = RegexEngine(pattern)

        let input = String(repeating: "a", count: 200) + "b"
        let match = try XCTUnwrap(engine.firstMatch(in: input))
        XCTAssertEqual(String(input[match.range]), input, "The whole string -- every 'a' plus the trailing 'b' -- should match")
    }
}
