# SwiftGrep: A Theoretical FSA Engine
`SwiftGrep` is a command-line utility and library designed to demonstrate the application of **Antimirov’s Partial Derivatives** in finite state automata. Unlike traditional regex engines that rely on backtracking (which can lead to catastrophic performance on specific inputs), this engine constructs ε-free NFAs directly from regular expressions.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2012%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Features
- **Antimirov Engine**: Uses partial derivatives to simulate NFA transitions without ε-closures.
- **Dynamic Capture**: Handles nested capture groups and dynamic backreferences.
- **Brzozowski Minimization**: Includes a native implementation of DFA minimization via the double-reversal `det(rev(det(rev(A))))` algorithm.
- **Leftmost-Longest Matching**: Implemented via NFA state-tracking that respects longest-match greedy semantics.
- **Streaming I/O**: Efficiently processes files using Swift’s `AsyncSequence` for line-by-line matching.

---

## Installation

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

Or build the CLI binary:
```bash

swift build -c release
./.build/release/sgrep "a(b|c)*" your_file.txt
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.  
