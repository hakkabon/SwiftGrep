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

public struct MatchState: Hashable {
    let regex: Regex
    let env: [Int: String]
}

public class RegexEngine {
    let pattern: Regex

    public init(_ pattern: Regex) {
        self.pattern = pattern
    }

    /// Evaluates the pattern. For Substring matching, the start state is constantly injected.
    public func firstMatch(in input: String) -> [Int: String]? {
        // Active state pool (NFA Simulator)
        var activeStates: Set<MatchState> = [MatchState(regex: pattern, env: [:])]
        var bestMatch: [Int: String]? = nil

        for char in input {
            // Nullability check on current states for earlier accepting states
            if let accepting = activeStates.first(where: { $0.regex.isNullable(env: $0.env) }) {
                if bestMatch == nil { bestMatch = accepting.env }
            }

            var nextStates: Set<MatchState> = []
            
            // Re-inject the initial pattern state to support arbitrary substring starting index
            nextStates.insert(MatchState(regex: pattern, env: [:]))

            for state in activeStates {
                let derivs = state.regex.derivative(with: char, env: state.env)
                for d in derivs {
                    var newEnv = state.env
                    // Map active group IDs to the environment
                    for capId in d.captures {
                        newEnv[capId, default: ""] += String(char)
                    }
                    nextStates.insert(MatchState(regex: d.regex, env: newEnv))
                }
            }
            activeStates = nextStates
        }

        // Final check at end of string
        if let accepting = activeStates.first(where: { $0.regex.isNullable(env: $0.env) }) {
            bestMatch = accepting.env
        }

        return bestMatch
    }
}
