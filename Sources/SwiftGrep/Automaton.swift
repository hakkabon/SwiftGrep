//
//  Automaton.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation


public struct Automaton<State: Hashable> {
    public var states: Set<State> = []
    public var alphabet: Set<Character> = []
    public var transitions: [State: [Character: Set<State>]] = [:]
    public var initialStates: Set<State> = []
    public var acceptingStates: Set<State> = []

    /// Reverses the automaton edges. Accept states become initial, initial become accept.
    public func reversed() -> Automaton<State> {
        var revTransitions = [State: [Character: Set<State>]]()
        for (u, edges) in transitions {
            for (char, vs) in edges {
                for v in vs {
                    revTransitions[v, default: [:]][char, default: []].insert(u)
                }
            }
        }
        return Automaton(
            states: states, alphabet: alphabet, transitions: revTransitions,
            initialStates: acceptingStates, acceptingStates: initialStates
        )
    }

    /// Applies the powerset (subset) construction to return an equivalent DFA
    public func determinized() -> Automaton<Set<State>> {
        var dfa = Automaton<Set<State>>(
            alphabet: alphabet,
            initialStates: [initialStates]
        )
        var unmarked: Set<Set<State>> = [initialStates]

        while let current = unmarked.popFirst() {
            dfa.states.insert(current)
            if !current.isDisjoint(with: acceptingStates) {
                dfa.acceptingStates.insert(current)
            }

            for char in alphabet {
                var nextSubset: Set<State> = []
                for state in current {
                    if let targets = transitions[state]?[char] {
                        nextSubset.formUnion(targets)
                    }
                }
                if !nextSubset.isEmpty {
                    dfa.transitions[current, default: [:]][char] = [nextSubset]
                    if !dfa.states.contains(nextSubset) {
                        unmarked.insert(nextSubset)
                        dfa.states.insert(nextSubset)
                    }
                }
            }
        }
        return dfa
    }

    /// Brzozowski Minimization: Min(A) = Det(Rev(Det(Rev(A))))
    public func minimized() -> Automaton<Set<Set<State>>> {
        return self.reversed().determinized().reversed().determinized()
    }
}

extension Regex {
    
    /// Statically constructs an ε-free NFA explicitly via Antimirov's Partial Derivatives.
    public func buildNFA(alphabet: Set<Character>) -> Automaton<Regex> {
        var nfa = Automaton<Regex>(alphabet: alphabet, initialStates: [self])
        var unmarked: Set<Regex> = [self]

        while let current = unmarked.popFirst() {
            nfa.states.insert(current)
            if current.isNullable(env: [:]) {
                nfa.acceptingStates.insert(current)
            }

            for char in alphabet {
                let targets = current.derivative(with: char, env: [:]).map { $0.regex }
                let nextStates = Set(targets)

                if !nextStates.isEmpty {
                    nfa.transitions[current, default: [:]][char] = nextStates
                }

                for n in nextStates {
                    if !nfa.states.contains(n) {
                        unmarked.insert(n)
                        nfa.states.insert(n)
                    }
                }
            }
        }
        return nfa
    }
}
