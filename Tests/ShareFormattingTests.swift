import Testing
@testable import NotesApp

struct ShareFormattingTests {
    @Test func blockquotesSingleLine() {
        #expect(ShareFormatting.blockquote("hello") == "> hello")
    }

    @Test func blockquotesEachLine() {
        #expect(ShareFormatting.blockquote("a\nb") == "> a\n> b")
    }

    @Test func blockquotePreservesBlankLines() {
        #expect(ShareFormatting.blockquote("a\n\nb") == "> a\n> \n> b")
    }
}
