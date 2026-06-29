import Foundation
@testable import NotesApp
import Testing

struct FrontmatterSerializerTests {
    // MARK: - Slugs

    @Test func slugKebabCasesAndStripsPunctuation() {
        #expect(FrontmatterSerializer.slug(from: "Hello, World!") == "hello-world")
    }

    @Test func slugRemovesFillerWords() {
        #expect(FrontmatterSerializer.slug(from: "The Quick Brown Fox") == "quick-brown-fox")
    }

    @Test func slugFallsBackWhenAllFiller() {
        #expect(FrontmatterSerializer.slug(from: "the and of") == "the-and-of")
    }

    @Test func slugReturnsUntitledForEmpty() {
        #expect(FrontmatterSerializer.slug(from: "   ") == "untitled")
    }

    @Test func slugCapsWordCount() {
        let slug = FrontmatterSerializer.slug(from: "one two three four five six seven eight nine ten")
        #expect(slug.split(separator: "-").count <= 8)
    }

    @Test func slugCapsLength() {
        let slug = FrontmatterSerializer.slug(from: String(repeating: "word ", count: 40))
        #expect(slug.count <= 60)
    }

    // MARK: - Dates

    @Test func dateRoundTripsInUTC() throws {
        let date = try #require(FrontmatterSerializer.date(from: "2026-06-29"))
        #expect(FrontmatterSerializer.dateString(date) == "2026-06-29")
    }

    // MARK: - Serialize

    @Test func serializeEmitsFrontmatterAndOmitsFalseDraft() {
        let note = Note(title: "My Title", body: "Hello body", pubDate: Date(timeIntervalSince1970: 0), draftFlag: false)
        let output = FrontmatterSerializer.serialize(note)
        #expect(output.hasPrefix("---\n"))
        #expect(output.contains("title: \"My Title\""))
        #expect(output.contains("pubDate: 1970-01-01"))
        #expect(output.contains("Hello body"))
        #expect(!output.contains("draft:"))
    }

    @Test func serializeIncludesOptionalFields() {
        let note = Note(
            title: "T",
            body: "b",
            sourceURL: "https://x.com",
            customSlug: "my-slug",
            tags: ["a", "b"],
            draftFlag: true
        )
        let output = FrontmatterSerializer.serialize(note)
        #expect(output.contains("sourceURL: https://x.com"))
        #expect(output.contains("slug: my-slug"))
        #expect(output.contains("draft: true"))
        #expect(output.contains("tags: [\"a\", \"b\"]"))
    }

    // MARK: - Parse

    @Test func parseExtractsAllFields() {
        let markdown = """
        ---
        title: "Hello"
        sourceURL: https://example.com
        draft: true
        pubDate: 2026-01-02
        tags: ["x", "y"]
        styleguide: true
        ---

        Body text here.
        """
        let parsed = FrontmatterSerializer.parse(markdown)
        #expect(parsed.title == "Hello")
        #expect(parsed.sourceURL == "https://example.com")
        #expect(parsed.draft)
        #expect(parsed.tags == ["x", "y"])
        #expect(parsed.styleguide)
        #expect(parsed.pubDate != nil)
        #expect(parsed.body.contains("Body text here."))
    }

    @Test func parseWithoutFrontmatterKeepsWholeBody() {
        let parsed = FrontmatterSerializer.parse("Just body, no frontmatter")
        #expect(parsed.title == "")
        #expect(parsed.body == "Just body, no frontmatter")
    }

    @Test func serializeParseRoundTrip() {
        let note = Note(
            title: "Round Trip",
            body: "Some body",
            sourceURL: "https://r.com",
            tags: ["t1"],
            pubDate: Date(timeIntervalSince1970: 0)
        )
        let parsed = FrontmatterSerializer.parse(FrontmatterSerializer.serialize(note))
        #expect(parsed.title == "Round Trip")
        #expect(parsed.sourceURL == "https://r.com")
        #expect(parsed.tags == ["t1"])
        #expect(parsed.body.trimmingCharacters(in: .whitespacesAndNewlines) == "Some body")
    }

    // MARK: - Hashing

    @Test func contentHashIsStableAndDistinct() {
        #expect(FrontmatterSerializer.contentHash(of: "abc") == FrontmatterSerializer.contentHash(of: "abc"))
        #expect(FrontmatterSerializer.contentHash(of: "abc") != FrontmatterSerializer.contentHash(of: "abd"))
    }
}
