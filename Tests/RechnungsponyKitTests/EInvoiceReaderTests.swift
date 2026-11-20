import XCTest
@testable import RechnungsponyKit

final class EInvoiceReaderTests: XCTestCase {
    func testRoundTripOfOwnXML() throws {
        let original = SampleInvoice.make()
        let attachment = InvoiceAttachment(fileName: "Zeitnachweis.pdf", mimeType: "application/pdf", data: Data("hallo".utf8))
        let xml = try CIIWriter().xml(for: original, profile: .zugferdEN16931, attachments: [attachment])

        let parsed = try EInvoiceReader().parse(xml: Data(xml.utf8))
        let invoice = parsed.invoice

        XCTAssertEqual(parsed.typeCode, "380")
        XCTAssertEqual(parsed.guidelineID, EInvoiceProfile.zugferdEN16931.guidelineID)
        XCTAssertEqual(parsed.warnings, [])
        XCTAssertEqual(invoice.number, original.number)
        XCTAssertEqual(invoice.issueDate, original.issueDate)
        XCTAssertEqual(invoice.serviceStart, original.serviceStart)
        XCTAssertEqual(invoice.serviceEnd, original.serviceEnd)
        XCTAssertEqual(invoice.dueDate, original.dueDate)
        XCTAssertEqual(invoice.paymentDueDays, 14)
        XCTAssertEqual(invoice.paymentTerms, original.paymentTerms)
        XCTAssertEqual(invoice.notes, original.notes)

        XCTAssertEqual(invoice.seller.name, original.seller.name)
        XCTAssertEqual(invoice.seller.street, original.seller.street)
        XCTAssertEqual(invoice.seller.vatID, original.seller.vatID)
        XCTAssertEqual(invoice.seller.email, original.seller.email)
        XCTAssertEqual(invoice.seller.contactName, original.seller.contactName)
        XCTAssertEqual(invoice.seller.contactPhone, original.seller.contactPhone)
        XCTAssertEqual(invoice.buyer.name, original.buyer.name)
        XCTAssertEqual(invoice.buyer.email, original.buyer.email)
        XCTAssertEqual(invoice.buyerReference, original.buyerReference)
        XCTAssertEqual(invoice.iban, original.iban)
        XCTAssertEqual(invoice.bic, original.bic)

        XCTAssertEqual(invoice.items.count, original.items.count)
        for (a, b) in zip(invoice.items, original.items) {
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.quantity, b.quantity)
            XCTAssertEqual(a.unitCode, b.unitCode)
            XCTAssertEqual(a.unitPrice, b.unitPrice)
            XCTAssertEqual(a.vatRate, b.vatRate)
        }
        XCTAssertEqual(invoice.netTotal, original.netTotal)
        XCTAssertEqual(invoice.grossTotal, original.grossTotal)
        XCTAssertEqual(parsed.declaredGross, original.grossTotal)
        XCTAssertEqual(parsed.declaredNet, original.netTotal)

        XCTAssertEqual(parsed.attachments.count, 1)
        XCTAssertEqual(parsed.attachments.first?.fileName, "Zeitnachweis.pdf")
        XCTAssertEqual(parsed.attachments.first?.data, attachment.data)
    }

    func testTypeCodeIsReported() throws {
        let xml = try CIIWriter().xml(for: SampleInvoice.make(), profile: .zugferdEN16931)
            .replacingOccurrences(of: "<ram:TypeCode>380</ram:TypeCode>", with: "<ram:TypeCode>381</ram:TypeCode>")
        XCTAssertEqual(try EInvoiceReader().parse(xml: Data(xml.utf8)).typeCode, "381")
    }

    func testSumMismatchProducesWarning() throws {
        let xml = try CIIWriter().xml(for: SampleInvoice.make(), profile: .zugferdEN16931)
            .replacingOccurrences(of: "<ram:GrandTotalAmount>", with: "<ram:GrandTotalAmount>9")
        let parsed = try EInvoiceReader().parse(xml: Data(xml.utf8))
        XCTAssertTrue(parsed.warnings.contains { $0.contains("weicht") })
    }

    func testRejectsOtherFormatsAndBrokenXML() {
        XCTAssertThrowsError(try EInvoiceReader().parse(xml: Data("<Invoice xmlns=\"urn:oasis\"/>".utf8)))
        XCTAssertThrowsError(try EInvoiceReader().parse(xml: Data("<foo/>".utf8)))
        XCTAssertThrowsError(try EInvoiceReader().parse(xml: Data("<rsm:CrossIndustryInvoice>".utf8)))
    }

    func testReadingPDFWithoutEmbeddedXMLFails() {
        let pdf = Data("%PDF-1.4\n1 0 obj\n<< >>\nendobj\ntrailer\n<< >>\n%%EOF\n".utf8)
        XCTAssertThrowsError(try EInvoiceReader().read(pdf))
    }
}
