//
//  Expression.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//

import Foundation

/// This is a fantastic and deeply theoretical project. To fulfill your
/// requirements, we need to bridge dynamic evaluation (for nested captures,
/// backreferences, and substring matching) with formal Automata theory
/// (Antimirov's construction and Brzozowski's minimization).

/// Regex AST & Simplifications
/// First, we set up the AST with intelligent constructors that aggressively simplify
/// the expression to prevent states from blowing up (especially ∅ dead paths).

public enum CharacterClassComponent: Hashable, CustomStringConvertible {
    case single(Character)
    case range(ClosedRange<Character>)

    public func contains(_ char: Character) -> Bool {
        switch self {
        case .single(let c): return c == char
        case .range(let r): return r.contains(char)
        }
    }

    public var description: String {
        switch self {
        case .single(let c): return String(c)
        case .range(let r): return "\(r.lowerBound)-\(r.upperBound)"
        }
    }
}

public indirect enum Regex: Hashable {
    case empty
    case epsilon
    case any  // Matches any single character (like '.')
    case symbol(Character)
    case alternation(Set<Regex>)
    case intersection(Set<Regex>)
    case negation(Regex)
    case concat(Regex, Regex)
    case star(Regex)
    case plus(Regex)
    case question(Regex)
    case characterClass(isNegated: Bool, Set<CharacterClassComponent>)
    case capture(id: Int, Regex)
    case backreference(id: Int)
    
    // Smart Constructors
    public static func alt(_ components: Set<Regex>) -> Regex {
        var flattened = Set<Regex>()
        for item in components {
            if case .alternation(let sub) = item { flattened.formUnion(sub) }
            else { flattened.insert(item) }
        }
        flattened.remove(.empty)
        if flattened.isEmpty { return .empty }
        if flattened.count == 1 { return flattened.first! }
        return .alternation(flattened)
    }
    
    public static func con(_ left: Regex, _ right: Regex) -> Regex {
        if left == .empty || right == .empty { return .empty }
        if left == .epsilon { return right }
        if right == .epsilon { return left }
        return .concat(left, right)
    }
    
    public static func cap(id: Int, _ op: Regex) -> Regex {
        if op == .empty { return .empty }
        return .capture(id: id, op)
    }

    public static func pl(_ op: Regex) -> Regex {
        if op == .empty { return .empty }
        if op == .epsilon { return .epsilon }
        return .plus(op)
    }

    public static func qn(_ op: Regex) -> Regex {
        if op == .empty { return .epsilon }
        if op == .epsilon { return .epsilon }
        return .question(op)
    }

    public static func cc(isNegated: Bool, _ components: Set<CharacterClassComponent>) -> Regex {
        if components.isEmpty {
            return isNegated ? .any : .empty
        }
        return .characterClass(isNegated: isNegated, components)
    }
}

extension Regex: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .empty: return "∅"
        case .epsilon: return "ε"
        case .any: return "."
        case .symbol(let c): return String(c)
        case .alternation(let s): return "(" + s.map(\.description).sorted().joined(separator: "|") + ")"
        case .intersection(let s): return "(" + s.map(\.description).sorted().joined(separator: "&") + ")"
        case .negation(let r): return "~\(r)"
        case .concat(let l, let r): return "\(l)\(r)"
        case .star(let r): return "(\(r))*"
        case .plus(let r): return "(\(r))+"
        case .question(let r): return "(\(r))?"
        case .characterClass(let isNegated, let components):
            let negatedPrefix = isNegated ? "^" : ""
            let body = components.map(\.description).sorted().joined()
            return "[\(negatedPrefix)\(body)]"
        case .capture(let id, let r): return "[\(id):\(r)]"
        case .backreference(let id): return "\\\(id)"
        }
    }
}
