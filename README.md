# SwiftGrep

`SwiftGrep` is a small, pure-Swift `grep`-like command-line tool and library built around an **automata-theoretic** regular expression engine. Instead of the backtracking strategy used by most "regex" implementations (including Swift's own `NSRegularExpression`/ICU and most scripting-language engines), `SwiftGrep` compiles patterns into a state machine using **Antimirov's partial derivatives** — a construction that turns the algebraic structure of the regular expression directly into an ε-free NFA, with no intermediate Thompson-style ε-transitions and no danger of catastrophic ("ReDoS") backtracking blow-up on the regular core of the language.

On top of that regular core, `SwiftGrep` layers an online, capture-aware simulator that additionally supports nested capturing groups and single-digit backreferences (`\1`–`\9`) — a deliberately non-regular extension, discussed in depth in [ALGORITHMS.md](ALGORITHMS.md), along with the complexity-theoretic trap that backreferences spring on any engine that supports them.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2012%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Table of Contents

1. [Features](#features)
2. [Installation](#installation)
   - [Swift Package Manager](#swift-package-manager)
   - [Building the CLI](#building-the-cli)
3. [Quick Start](#quick-start)
   - [Command-Line Usage](#command-line-usage)
   - [Library Usage](#library-usage)
4. [Supported Regex Syntax](#supported-regex-syntax)
5. [Architecture / Source Layout](#architecture--source-layout)
6. [How Matching Works](#how-matching-works)
7. [Known Limitations &amp; Roadmap](#known-limitations--roadmap)
8. [Testing](#testing)
9. [License](#license)

---

## Features

- **Antimirov partial-derivative engine.** Patterns are not interpreted by a backtracking VM; they are turned into an ε-free NFA where every *state is itself a regular-expression term* and every *transition is the partial derivative* of that term with respect to an input character. See [ALGORITHMS.md](ALGORITHMS.md) for the full theory.
- **Hand-written lexer & recursive-descent parser.** `Tokenizer.swift` and `RegexParser.swift` implement the entire pattern-string → AST pipeline locally, with correct operator precedence (`*` binds tighter than concatenation, which binds tighter than `|`) and no external lexer/parser dependency.
- **Capturing groups & backreferences.** Capture groups are numbered left-to-right by their opening `(`, and can be referenced with `\1`–`\9`. Because backreferences make the language non-regular (see [ALGORITHMS.md](ALGORITHMS.md)), they are handled by an online NFA simulation (`RegexEngine`) that carries a capture environment alongside each active state, rather than by the static `Automaton` construction.
- **Leftmost-longest matching.** `RegexEngine.firstMatch(in:)` tracks every live match attempt (one per possible start index) in parallel and reports the match that starts earliest, breaking ties by length — the same semantic POSIX `grep` uses, and notably *not* "first alternative that happens to match," which is what backtracking engines typically give you.
- **Brzozowski minimization for the regular core.** `Automaton.minimized()` implements the elegant `det(rev(det(rev(A))))` double-reversal algorithm to compute the unique minimal DFA for any backreference-free pattern, alongside `reversed()` and `determinized()` (powerset construction) as standalone, independently useful operations.
- **`sgrep` CLI**, built on `swift-argument-parser`, supporting:
  - searching one or more files, or standard input when no files are given;
  - `-l/--line-number` to prefix matches with their 1-based line number;
  - `-i/--invert-match` to print only non-matching lines (POSIX `grep -v` semantics);
  - asynchronous, line-by-line streaming via `URL.lines` / `FileHandle.standardInput.bytes.lines`, so large files are not read into memory at once.
- **ANSI match highlighting helper.** `String.highlighted(in:)` wraps a matched range in bold-red terminal escape codes. (As of this writing it's exercised in the test suite but not yet wired into the `sgrep` executable's own output — see [Known Limitations](#known-limitations--roadmap).)
- **Zero regex-engine dependencies.** The only external dependency is `swift-argument-parser`, used solely by the CLI target; the `SwiftGrep` library target has none.

---

## Installation

### Swift Package Manager

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/SwiftGrep.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftGrep", package: "SwiftGrep"),
        ]
    ),
]
```

### Building the CLI

```bash
swift build -c release
./.build/release/sgrep "a(b|c)*" your_file.txt
```

---

## Quick Start

### Command-Line Usage

```bash
# Search a file
sgrep "error|warning" server.log

# Prefix matches with line numbers
sgrep -l "TODO" Sources/**/*.swift

# Invert the match (print lines that do NOT match), grep -v style
sgrep -i "DEBUG" app.log

# Read from standard input when no files are given
cat access.log | sgrep "5\d\d"   # NB: \d is not a supported escape — see below
```

### Library Usage

```swift
import SwiftGrep

// 1. Parse a pattern string into a `Regex` AST.
let ast = try RegexParser.parse("a(bc|bd)*")

// 2. Drive it with the online matching engine.
let engine = RegexEngine(ast)

if let match = engine.firstMatch(in: "xx abcbdbc yy") {
    print(match.range)      // Range<String.Index> — the matched substring's bounds
    print(match.captures)   // [Int: String] — text captured by each group id
}

// 3. Highlight a match for terminal output.
if let match = engine.firstMatch(in: "xx abcbdbc yy") {
    print("xx abcbdbc yy".highlighted(in: match.range))
}
```

You can also build and minimize a *static* automaton directly from a `Regex` AST — but only for the **backreference-free, intersection/negation-free** subset of the language, since those constructs are not (yet, or ever, in the case of backreferences) regular:

```swift
let pattern = try RegexParser.parse("a(b|c)*")
let alphabet: Set<Character> = ["a", "b", "c"]

let nfa = pattern.buildNFA(alphabet: alphabet)   // Antimirov ε-free NFA
let dfa = nfa.minimized()                        // Brzozowski double-reversal minimization

print("NFA states:", nfa.states.count)
print("Minimal DFA states:", dfa.states.count)
```

---

## Supported Regex Syntax

| Syntax        | Meaning                                             | Example                              |  
|---------------|------------------------------------------------------|---------------------------------------|  
| `a`, `b`, …   | A literal character                                  | `cat` matches `"cat"`                  |  
| `.`           | Any single character                                 | `c.t` matches `"cat"`, `"cot"`, …       |  
| `R1\|R2`      | Alternation                                          | `cat\|dog`                             |  
| `R*`          | Zero-or-more repetition (Kleene star)                 | `ab*c` matches `"ac"`, `"abc"`, `"abbc"` |  
| `(R)`         | Capturing group, numbered left-to-right by `(`        | `(ab)(cd)` — group 1 is `ab`, group 2 is `cd` |  
| `\1` … `\9`   | Backreference to capture group 1–9                    | `(a\|b)\1` matches `"aa"` or `"bb"`, not `"ab"` |  
| `\x`          | Escaped literal, for any `x` that is not a non-zero digit | `\.` matches a literal `"."`; `\\` matches `"\"` |  

Everything else in the input string is taken as a literal character — there is no special meaning for, e.g., `[`, `]`, `^`, `$`, `+`, `?`, or `{`/`}` today (see below).

### Not Yet Supported

The `Regex` AST already has cases for some operators that the textual grammar can't yet produce, and the textual grammar itself has clear gaps. Both are good entry points for contribution:

- Quantifiers `+`, `?`, and bounded repetition `{m,n}` (today, only `*` exists; `a+` must be written as `aa*`).
- Character classes `[abc]`, `[^abc]`, and ranges `[a-z]`.
- Anchors `^` and `$`.
- Multi-digit backreferences: `\10` tokenizes as `\1` followed by a literal `"0"`, not "backreference 10" (see [ALGORITHMS.md](ALGORITHMS.md) for why, and [Tests](#testing) for a regression test that pins this behavior down).
- `Regex.intersection` and `Regex.negation` exist as AST cases for *programmatic* construction (e.g. if you're building ASTs by hand rather than through `RegexParser`), but `derivative(with:env:)` currently calls `fatalError()` for both — there is no textual syntax that reaches them, and you should not call `buildNFA` or `RegexEngine` on an AST that contains them. See [ALGORITHMS.md](ALGORITHMS.md) for *why* this is a harder problem than it looks.

---

## Architecture / Source Layout

```
Sources/
├── SwiftGrep/                  the library target
│   ├── Tokenizer.swift         hand-written lexer: String -> [Token]; also defines Token & ParseError
│   ├── RegexParser.swift       recursive-descent parser: [Token] -> Regex AST
│   ├── Expression.swift        the `Regex` AST + "smart constructors" (con, alt, cap)
│   ├── Derivative.swift        isNullable + derivative(with:env:) — the Antimirov partial derivative
│   ├── Engine.swift            RegexEngine — online, capture-aware NFA simulation
│   ├── Automaton.swift         generic Automaton<State>, reversed/determinized/minimized, buildNFA
│   └── String+extension.swift  ANSI highlight helper
└── sgrep/                      the CLI executable target
    ├── Sgrep.swift             ArgumentParser command, stdin handling, -l/-i flags
    └── FileIO.swift            async, line-by-line file processing

Tests/
└── SwiftGrepTests/
    ├── RegexParserTests.swift          basic AST shape checks (Swift Testing)
    ├── RegexEngineTests.swift          example-driven engine usage (Swift Testing)
    ├── RegularExpressionTests.swift    the original broad XCTest suite
    ├── TokenizerTests.swift            lexer edge cases (new)
    ├── RegexParserAdditionalTests.swift   parser precedence/error-path coverage (new)
    ├── MatchingCornerCaseTests.swift   leftmost-longest, captures, backreferences, ReDoS-shaped patterns (new)
    └── AutomatonTests.swift            NFA/DFA language-equivalence & minimization checks (new)
```

A pattern flows through the system as: **string** → (`Tokenizer`) → **`[Token]`** → (`RegexParser`) → **`Regex` AST** → (`Derivative` + `Engine`, *or* `Automaton.buildNFA`/`minimized`) → **match result**.

> **Note on the package dependency graph:** earlier revisions of `Package.swift` depended on an external `hakkabon/GrammarTokenizer` package for lexing, but it was never actually imported by any source file — `Tokenizer.swift` in this package is the local, self-contained replacement. That unused dependency has been removed from `Package.swift`.

---

## How Matching Works

The short version: a `Regex` AST node *is* an NFA state. Consuming a character `c` from a state `R` doesn't require simulating ε-closures over a separately constructed transition table — you just compute `R`'s **partial derivative** with respect to `c`, which symbolically rewrites `R` into the set of regex terms describing "what's left to match." `isNullable` plays the role of "is this state accepting." `Automaton.buildNFA` simply runs that process as a worklist/fixpoint algorithm, discovering states (terms) and transitions as it goes, and `minimized()` then collapses the result to the unique minimal DFA via Brzozowski's `det(rev(det(rev(A))))` trick.

Backreferences break this picture, because the "state" needed to decide whether `\1` matches isn't just an AST node — it's the AST node *plus* everything captured so far. That dependency on history is exactly what makes backreferenced patterns non-regular (and, in the worst case, NP-complete to match), so `RegexEngine` handles them with an online simulation that carries a capture environment, rather than a precompiled automaton.

The full derivation, the relevant theorems and their proofs sketches, worked examples, and — at the request that motivated this document — a careful explanation of how backreferences relate to intractability and undecidability in computer science, live in **[ALGORITHMS.md](ALGORITHMS.md)**.

---

## Known Limitations & Roadmap

- **Single-digit backreferences only.** `\1`–`\9` are supported; `\10` is tokenized as `\1` followed by a literal `"0"` character, not as "backreference 10." (Verified by `TokenizerTests.testMultiDigitBackreferenceIsNotSupported`.)
- **No character classes, bounded quantifiers, or anchors** in the textual grammar yet (the underlying `Regex` AST has room to grow; the bottleneck is `Tokenizer`/`RegexParser`).
- **`.intersection` / `.negation` will crash the matcher.** They exist on the `Regex` enum for programmatic AST construction, but `derivative(with:env:)` has no implementation for them yet (`fatalError`). There is no path from `RegexParser` that produces them, so this only matters if you build a `Regex` value by hand.
- **Repeated-capture semantics differ from PCRE/Perl.** For a pattern like `(a)*` matched against `"aaa"`, this engine's capture environment *accumulates* the text consumed across every iteration of the group (`captures[1] == "aaa"`), rather than keeping only the most recent iteration (`captures[1] == "a"` in PCRE/Perl). This is a deliberate consequence of how the capture environment is threaded through `derivative(...)`, not a bug — but it's worth knowing if you're porting patterns from another engine. See `MatchingCornerCaseTests.testRepeatedCaptureGroupAccumulatesAcrossIterations`.
- **Forward/dangling backreferences match vacuously.** `\1(a)` is accepted by the parser (no "undefined group" error) and, because an unset capture is treated as nullable, the leading `\1` is simply skipped the first time through. Most PCRE-style engines either reject this pattern statically or always fail it at match time. See `MatchingCornerCaseTests.testForwardBackreferenceIsTreatedAsVacuouslyNullable`.
- **`buildNFA`/`minimized()` are for the backreference-free subset only.** Any pattern using `\1`–`\9` must go through `RegexEngine`; the static `Automaton` machinery has no notion of a capture environment.
- **The CLI doesn't highlight matches yet.** `String.highlighted(in:)` exists and is tested, but neither `Sgrep.swift` nor `FileIO.swift` calls it — `sgrep` currently prints matched lines in plain text. Wiring this up (behind a `--color` flag, perhaps) is a good first contribution.
- **`Automaton.minimized()` can be exponential in the worst case**, since each of its two determinization passes is a powerset construction. This is a known, accepted property of Brzozowski's algorithm (not a bug) — see [ALGORITHMS.md](ALGORITHMS.md) for the tradeoff against, e.g., Hopcroft's partition-refinement algorithm.

---

## Testing

```bash
swift test
```

The suite mixes `XCTest` and the newer `Testing` framework (both are supported side-by-side by the same test target). Coverage spans: AST smart-constructor simplification, nullability, the tokenizer/lexer, parser precedence and error paths, substring/leftmost-longest matching, nested captures and backreferences, NFA construction, and Brzozowski minimization — including several language-equivalence checks that simulate an NFA and its minimized DFA side-by-side and assert they accept exactly the same strings.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
