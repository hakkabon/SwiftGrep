//
//  Engine.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// Because backreferences and captures are inherently non-regular,
/// they cannot be pre-compiled into a classical minimal DFA. We use
/// an active state simulator to perform substring matching.

public struct MatchResult {
    public let range: Range<String.Index>
    public let captures: [Int: String]
}

/// To implement Advanced Visual Output (color highlighting), we need to
/// track exactly where a match begins and ends in the input string.
/// We can achieve this by modifying the RegexEngine to use Swift's String.Index.
/// Instead of just holding the regex AST and the captured environment, our NFA
/// simulator states must also carry the starting index of their respective match
/// attempt. By tracking the startIndex, and checking the current index whenever
/// an NFA state becomes "nullable" (accepting), we naturally obtain the
/// Range<String.Index>.

public struct MatchState: Hashable {
    let regex: Regex
    let env: [Int: String]
    let startIndex: String.Index // Tracks where this specific execution path began
}

public class RegexEngine {
    let pattern: Regex
    
    public init(_ pattern: Regex) {
        self.pattern = pattern
    }

    public func firstMatch(in input: String) -> MatchResult? {
        var activeStates: Set<MatchState> = []
        var bestMatch: MatchResult? = nil
        
        // Edge case: check if the pattern matches an empty string immediately at the start
        if pattern.isNullable(env: [:]) {
            bestMatch = MatchResult(range: input.startIndex..<input.startIndex, captures: [:])
        }
        
        for index in input.indices {
            let char = input[index]
            let nextIndex = input.index(after: index)
            
            // Inject a new start state at the current character index.
            // This allows the engine to begin a new substring match anywhere.
            activeStates.insert(MatchState(regex: pattern, env: [:], startIndex: index))
            
            var nextStates: Set<MatchState> = []
            
            for state in activeStates {
                let derivatives = state.regex.derivative(with: char, env: state.env)
                
                for d in derivatives {
                    var newEnv = state.env
                    // Map active group IDs to the environment
                    for capId in d.captures {
                        newEnv[capId, default: ""] += String(char)
                    }
                    
                    let nextState = MatchState(regex: d.regex, env: newEnv, startIndex: state.startIndex)
                    
                    // If this path accepts, evaluate it as a candidate for bestMatch
                    if nextState.regex.isNullable(env: nextState.env) {
                        let candidate = MatchResult(range: nextState.startIndex..<nextIndex, captures: nextState.env)
                        
                        if let best = bestMatch {
                            // Leftmost-Longest matching logic:
                            if candidate.range.lowerBound < best.range.lowerBound {
                                bestMatch = candidate // 1. Prefer earlier start
                            } else if candidate.range.lowerBound == best.range.lowerBound {
                                if candidate.range.upperBound > best.range.upperBound {
                                    bestMatch = candidate // 2. Prefer longer match
                                }
                            }
                        } else {
                            bestMatch = candidate
                        }
                    }
                    
                    nextStates.insert(nextState)
                }
            }
            activeStates = nextStates
        }
        
        return bestMatch
    }
}
