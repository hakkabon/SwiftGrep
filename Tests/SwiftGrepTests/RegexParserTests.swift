import Testing
@testable import SwiftGrep

@Test()
func testParserAST() async throws {
    do {
        // Translates to: a(b(c))\2
        // Which means: Match 'a', then group 1 capturing 'b' and group 2 capturing 'c',
        // then expect backreference \2 (which requires 'c' again)
        let ast = try RegexParser.parse("a(b(c))\\2")
        
        print(ast)
        // Expected description formatting based on your AST:
        // a[1:b[2:c]]\2
        
    } catch {
        print("Failed to parse: \(error)")
    }
}
