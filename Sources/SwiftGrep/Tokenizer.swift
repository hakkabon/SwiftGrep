//
//  Tokenizer.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/17.
//

import Foundation

// MARK: - Tokenizer / Lexer

public enum Token: Equatable, CustomStringConvertible {
    case char(Character)
    case dot        // .
    case pipe       // |
    case star       // *
    case plus       // +
    case question   // ?
    case lParen     // (
    case rParen     // )
    case lBracket   // [
    case rBracket   // ]
    case backref(Int) // \1, \2, etc.
    case eof

    public var description: String {
        switch self {
        case .char(let c): return String(c)
        case .dot: return "."
        case .pipe: return "|"
        case .star: return "*"
        case .plus: return "+"
        case .question: return "?"
        case .lParen: return "("
        case .rParen: return ")"
        case .lBracket: return "["
        case .rBracket: return "]"
        case .backref(let id): return "\\\(id)"
        case .eof: return "EOF"
        }
    }

    public var literalCharacter: Character? {
        switch self {
        case .char(let c): return c
        case .dot: return "."
        case .pipe: return "|"
        case .star: return "*"
        case .plus: return "+"
        case .question: return "?"
        case .lParen: return "("
        case .rParen: return ")"
        case .lBracket: return "["
        case .rBracket: return "]"
        case .backref(let id): return Character(String(id))
        case .eof: return nil
        }
    }
}

public enum ParseError: Error, CustomStringConvertible {
    case unexpectedToken(String)
    case missingClosingParen
    case missingClosingBracket
    case invalidEscapeSequence
    case nothingToRepeat
    
    public var description: String {
        switch self {
        case .unexpectedToken(let msg): return "Parse Error: Unexpected token '\(msg)'"
        case .missingClosingParen: return "Parse Error: Missing closing parenthesis ')'"
        case .missingClosingBracket: return "Parse Error: Missing closing bracket ']'"
        case .invalidEscapeSequence: return "Parse Error: Invalid escape sequence"
        case .nothingToRepeat: return "Parse Error: Quantifier '*' requires a preceding element"
        }
    }
}

public class Tokenizer {
    public static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        var index = input.startIndex
        
        while index < input.endIndex {
            let char = input[index]
            switch char {
            case ".": tokens.append(.dot)
            case "|": tokens.append(.pipe)
            case "*": tokens.append(.star)
            case "+": tokens.append(.plus)
            case "?": tokens.append(.question)
            case "(": tokens.append(.lParen)
            case ")": tokens.append(.rParen)
            case "[": tokens.append(.lBracket)
            case "]": tokens.append(.rBracket)
            case "\\":
                index = input.index(after: index)
                guard index < input.endIndex else { throw ParseError.invalidEscapeSequence }
                let escapedChar = input[index]
                if let digit = escapedChar.wholeNumberValue, digit > 0 {
                    tokens.append(.backref(digit))
                } else {
                    // Escaped literals: \* , \| , \\ , etc.
                    tokens.append(.char(escapedChar))
                }
            default:
                tokens.append(.char(char))
            }
            index = input.index(after: index)
        }
        tokens.append(.eof)
        return tokens
    }
}

// MARK: - Recursive Descent Parser

