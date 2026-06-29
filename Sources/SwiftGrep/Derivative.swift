//
//  Derivative.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

/// Nullability and Antimirov's Partial Derivatives
/// Here we implement `derivative`. Because we are dealing with dynamic matching,
/// the partial derivative naturally computes the ε-free NFA transitions,
/// while simultaneously surfacing which capture groups consumed the symbol.

public struct DerivResult: Hashable {
    public let regex: Regex
    public let captures: Set<Int> // Capture IDs active during this transition
}

extension Regex {
    
    public func isNullable(env: [Int: String]) -> Bool {
        switch self {
        case .empty, .any, .symbol, .characterClass: return false
        case .epsilon, .star, .question: return true
        case .plus(let r): return r.isNullable(env: env)
        case .alternation(let s): return s.contains { $0.isNullable(env: env) }
        case .intersection(let s): return s.allSatisfy { $0.isNullable(env: env) }
        case .negation(let r): return !r.isNullable(env: env)
        case .concat(let l, let r): return l.isNullable(env: env) && r.isNullable(env: env)
        case .capture(_, let r): return r.isNullable(env: env)
        case .backreference(let id): return env[id]?.isEmpty ?? true
        }
    }

    /// Evaluates the Antimirov partial derivative (returning NFA transition targets)
    public func derivative(with c: Character, env: [Int: String]) -> Set<DerivResult> {
        switch self {
        case .empty, .epsilon:
            return []
            
        case .any:
            return [DerivResult(regex: .epsilon, captures: [])]
            
        case .symbol(let char):
            return char == c ? [DerivResult(regex: .epsilon, captures: [])] : []

        case .characterClass(let isNegated, let components):
            let matches = components.contains { $0.contains(c) }
            let isMatch = isNegated ? !matches : matches
            return isMatch ? [DerivResult(regex: .epsilon, captures: [])] : []
            
        case .backreference(let id):
            guard let saved = env[id], !saved.isEmpty else { return [] }
            let chars = Array(saved)
            if chars[0] == c {
                if chars.count == 1 { return [DerivResult(regex: .epsilon, captures: [])] }
                let remRegex = chars[1...].reduce(Regex.epsilon) { Regex.con($0, .symbol($1)) }
                return [DerivResult(regex: remRegex, captures: [])]
            }
            return []
            
        case .capture(let id, let op):
            let nextOps = op.derivative(with: c, env: env)
            return Set(nextOps.compactMap { d -> DerivResult? in
                let nextRegex = Regex.cap(id: id, d.regex)
                if nextRegex == .empty { return nil }
                var caps = d.captures
                caps.insert(id) // Mark this capture group as having successfully digested 'c'
                return DerivResult(regex: nextRegex, captures: caps)
            })
            
        case .alternation(let set):
            return set.reduce(into: []) { $0.formUnion($1.derivative(with: c, env: env)) }
            
        case .concat(let l, let r):
            var result = Set<DerivResult>()
            for d in l.derivative(with: c, env: env) {
                let conRegex = Regex.con(d.regex, r)
                if conRegex != .empty {
                    result.insert(DerivResult(regex: conRegex, captures: d.captures))
                }
            }
            if l.isNullable(env: env) {
                result.formUnion(r.derivative(with: c, env: env))
            }
            return result
            
        case .star(let op):
            var result = Set<DerivResult>()
            for d in op.derivative(with: c, env: env) {
                let conRegex = Regex.con(d.regex, self)
                if conRegex != .empty {
                    result.insert(DerivResult(regex: conRegex, captures: d.captures))
                }
            }
            return result

        case .plus(let op):
            var result = Set<DerivResult>()
            for d in op.derivative(with: c, env: env) {
                let conRegex = Regex.con(d.regex, .star(op))
                if conRegex != .empty {
                    result.insert(DerivResult(regex: conRegex, captures: d.captures))
                }
            }
            return result

        case .question(let op):
            return op.derivative(with: c, env: env)
            
        case .intersection(_), .negation(_):
            // Fallback: pure NFA isn't natively closed under negation without subset determinization.
            // In a robust engine, evaluate this specific transition as a Brzozowski DFA proxy step.
            fatalError("Intersection & Negation require deterministic derivative fallbacks for Antimirov")
        }
    }
}
