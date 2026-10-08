import XCTest
@testable import InvoiceKit

final class AttachmentTests: XCTestCase {
    func testXMLContainsAttachment() throws {
        let att = InvoiceAttachment(fileName: "Zeitnachweis.pdf", mimeType: "application/pdf", data: Data("hallo".utf8))
        let xml = try CIIWriter().xml(for: SampleInvoice.make(), profile: .zugferdEN16931, attachments: [att])
        XCTAssertTrue(xml.contains("<ram:AdditionalReferencedDocument>"))
        XCTAssertTrue(xml.contains("mimeCode=\"application/pdf\" filename=\"Zeitnachweis.pdf\">aGFsbG8=<"))
    }

    func testMimeTypes() {
        XCTAssertEqual(InvoiceAttachment.mimeType(forExtension: "PDF"), "application/pdf")
        XCTAssertEqual(InvoiceAttachment.mimeType(forExtension: "jpeg"), "image/jpeg")
        XCTAssertNil(InvoiceAttachment.mimeType(forExtension: "docx"))
    }
}
