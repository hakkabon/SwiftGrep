//
//  RegexParser.swift
//  SwiftGrep
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/16.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation

public class RegexParser {
    private let tokens: [Token]
    private var pos: Int = 0
    private var nextCaptureId: Int = 1
    
    public init(tokens: [Token]) {
        self.tokens = tokens
    }
    
    // A standard recursive descent parser would go here.
    // It reads tokens, handles operator precedence (* is higher than concat,
    // concat is higher than |), and returns your `Regex` enum.
    
    // Example handling of escaping: "\1" -> .backreference(1)
    // Example handling of groups: "(...)" -> .capture(...)
    // fatalError("Requires a Lexer/Parser implementation")
    
    

    // MARK: Grammar Rules
    
    /// Root rule: Match an expression, expect EOF.
    private func parseRegex() throws -> Regex {
        let ast = try parseAlternation()
        let current = peek()
        guard current == .eof else {
            throw ParseError.unexpectedToken(current.description)
        }
        return ast
    }
    
    /// Rule 1: Alternation (Lowest Precedence)
    /// Alt -> Concat ("|" Concat)*
    private func parseAlternation() throws -> Regex {
        var nodes: [Regex] = [try parseConcat()]
        
        while match(.pipe) {
            nodes.append(try parseConcat())
        }
        
        return Regex.alt(Set(nodes))
    }
    
    /// Rule 2: Concatenation
    /// Concat -> Quantifier (Quantifier)*
    private func parseConcat() throws -> Regex {
        var nodes: [Regex] = []
        
        while true {
            let token = peek()
            // Tokens that terminate a concatenation block
            if token == .eof || token == .pipe || token == .rParen {
                break
            }
            nodes.append(try parseQuantifier())
        }
        
        // Empty sequence becomes epsilon (e.g., empty parens `()` or `a|` -> `a|ε`)
        if nodes.isEmpty { return .epsilon }
        
        // Fold from left to right: [a, b, c] -> con(con(a, b), c)
        return nodes[1...].reduce(nodes[0]) { Regex.con($0, $1) }
    }
    
    /// Rule 3: Quantifiers
    /// Quantifier -> Base ("*" | "+" | "?")*
    private func parseQuantifier() throws -> Regex {
        if peek() == .star || peek() == .plus || peek() == .question {
            throw ParseError.nothingToRepeat
        }
        
        var node = try parseBase()
        
        while true {
            let token = peek()
            if token == .star {
                consume()
                node = .star(node)
            } else if token == .plus {
                consume()
                node = Regex.pl(node)
            } else if token == .question {
                consume()
                node = Regex.qn(node)
            } else {
                break
            }
        }
        
        return node
    }
    
    /// Rule 4: Base Elements
    /// Base -> Char | "." | "(" Alt ")" | "\" Digit | "[" Class "]"
    private func parseBase() throws -> Regex {
        let token = consume()
        
        switch token {
        case .char(let c):
            return .symbol(c)
            
        case .dot:
            return .any
            
        case .backref(let id):
            return .backreference(id: id)
            
        case .lParen:
            // Standard Regex numbers capture groups sequentially by the opening parenthesis `(`
            let captureId = nextCaptureId
            nextCaptureId += 1
            
            // Sub-expression inside parenthesis
            let innerAst = try parseAlternation()
            
            guard match(.rParen) else {
                throw ParseError.missingClosingParen
            }
            return .capture(id: captureId, innerAst)

        case .lBracket:
            return try parseCharacterClass()
            
        default:
            throw ParseError.unexpectedToken(token.description)
        }
    }

    private func parseCharacterClass() throws -> Regex {
        // We have already consumed `.lBracket`
        var isNegated = false
        if case .char("^") = peek() {
            consume()
            isNegated = true
        }
        
        var components = Set<CharacterClassComponent>()
        
        while peek() != .rBracket {
            let token = peek()
            if token == .eof {
                throw ParseError.missingClosingBracket
            }
            
            guard let char = token.literalCharacter else {
                throw ParseError.unexpectedToken(token.description)
            }
            
            consume()
            
            if case .char("-") = peek() {
                // Peek next token after the dash
                if pos < tokens.count - 1 {
                    let nextNextToken = tokens[pos + 1]
                    if nextNextToken != .rBracket, let endChar = nextNextToken.literalCharacter {
                        consume() // consume `.char("-")`
                        consume() // consume `endChar`
                        
                        guard char <= endChar else {
                            throw ParseError.unexpectedToken("Invalid character range \(char)-\(endChar)")
                        }
                        components.insert(.range(char...endChar))
                        continue
                    }
                }
            }
            
            components.insert(.single(char))
        }
        
        guard match(.rBracket) else {
            throw ParseError.unexpectedToken(peek().description)
        }
        
        return Regex.cc(isNegated: isNegated, components)
    }
}

extension RegexParser {
    
    // MARK: Token Consumption Helpers
    
    private func peek() -> Token {
        guard pos < tokens.count else { return .eof }
        return tokens[pos]
    }
    
    @discardableResult
    private func consume() -> Token {
        let token = peek()
        if pos < tokens.count { pos += 1 }
        return token
    }
    
    private func match(_ expected: Token) -> Bool {
        if peek() == expected {
            consume()
            return true
        }
        return false
    }
}

extension RegexParser {

    /// Entry point to parse a raw string into a Regex AST
    public static func parse(_ input: String) throws -> Regex {
        let tokens = try Tokenizer.tokenize(input)
        let parser = RegexParser(tokens: tokens)
        return try parser.parseRegex()
    }
}
