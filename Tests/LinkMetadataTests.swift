import Foundation
@testable import NotesApp
import Testing

struct LinkMetadataTests {
    private let url = URL(string: "https://www.example.com/page")!

    @Test func extractsOpenGraphTags() {
        let html = """
        <html><head>
        <meta property="og:title" content="The Title">
        <meta property="og:description" content="A description">
        <meta property="og:image" content="https://cdn.example.com/img.png">
        </head></html>
        """
        let metadata = LinkMetadataService.parse(html: html, url: url)
        #expect(metadata.title == "The Title")
        #expect(metadata.description == "A description")
        #expect(metadata.imageURL?.absoluteString == "https://cdn.example.com/img.png")
        #expect(metadata.domain == "example.com")
    }

    @Test func titleFallsBackThroughPrecedence() {
        let twitterOnly = "<html><head><meta name=\"twitter:title\" content=\"TW\"></head></html>"
        #expect(LinkMetadataService.parse(html: twitterOnly, url: url).title == "TW")

        let titleTagOnly = "<html><head><title>Doc Title</title></head></html>"
        #expect(LinkMetadataService.parse(html: titleTagOnly, url: url).title == "Doc Title")
    }

    @Test func relativeImageResolvesToAbsolute() {
        let html = "<meta property=\"og:image\" content=\"/assets/cover.jpg\">"
        let metadata = LinkMetadataService.parse(html: html, url: url)
        #expect(metadata.imageURL?.absoluteString == "https://www.example.com/assets/cover.jpg")
    }

    @Test func decodesHTMLEntities() {
        let html = "<meta property=\"og:title\" content=\"Tom &amp; Jerry\">"
        #expect(LinkMetadataService.parse(html: html, url: url).title == "Tom & Jerry")
    }

    @Test func fallsBackToDomainWhenNoMetadata() {
        let metadata = LinkMetadataService.parse(html: "<html></html>", url: url)
        #expect(metadata.title == "example.com")
        #expect(metadata.description == nil)
        #expect(metadata.imageURL == nil)
    }
}
