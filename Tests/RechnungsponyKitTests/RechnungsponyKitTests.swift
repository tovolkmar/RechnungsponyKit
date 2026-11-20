import XCTest
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import RechnungsponyKit

final class RechnungsponyKitTests: XCTestCase {

    // MARK: - Beträge

    func testTotals() {
        let invoice = SampleInvoice.make()
        XCTAssertEqual(invoice.netTotal, dec("1600.00"))
        XCTAssertEqual(invoice.taxTotal, dec("304.00"))
        XCTAssertEqual(invoice.grossTotal, dec("1904.00"))
        XCTAssertEqual(invoice.vatBreakdown.count, 1)
    }

    func testRoundingHalfUp() {
        XCTAssertEqual(dec("0.125").rounded2(), dec("0.13"))
        XCTAssertEqual(dec("2.675").rounded2(), dec("2.68"))
        XCTAssertEqual(dec("1.004").rounded2(), dec("1.00"))
    }

    func testMixedVATRates() {
        var invoice = SampleInvoice.make()
        invoice.items.append(LineItem(name: "Buch", quantity: dec("3"), unitCode: "C62", unitLabel: "Stk.", unitPrice: dec("19.99"), vatRate: dec("7")))
        XCTAssertEqual(invoice.vatBreakdown.count, 2)
        // 3 × 19,99 = 59,97; 7 % = 4,1979 → 4,20
        let reduced = invoice.vatBreakdown.first { $0.rate == dec("7") }
        XCTAssertEqual(reduced?.tax, dec("4.20"))
    }

    // MARK: - XML

    func testXMLIsWellFormedAndContainsProfile() throws {
        let invoice = SampleInvoice.make()
        for profile in [EInvoiceProfile.zugferdEN16931, .xrechnung] {
            let xml = try CIIWriter().xml(for: invoice, profile: profile)
            let parser = XMLParser(data: Data(xml.utf8))
            XCTAssertTrue(parser.parse(), "XML nicht wohlgeformt: \(String(describing: parser.parserError))")
            XCTAssertTrue(xml.contains(profile.guidelineID))
            XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>1904.00</ram:GrandTotalAmount>"))
            XCTAssertTrue(xml.contains("<ram:DuePayableAmount>1904.00</ram:DuePayableAmount>"))
        }
    }

    func testPaymentMeansIsSEPACreditTransfer() throws {
        let xml = try CIIWriter().xml(for: SampleInvoice.make(), profile: .zugferdEN16931)
        let means = try XCTUnwrap(xml.range(of: "<ram:SpecifiedTradeSettlementPaymentMeans>"))
        XCTAssertTrue(xml[means.upperBound...].drop(while: \.isWhitespace).hasPrefix("<ram:TypeCode>58</ram:TypeCode>"))
    }

    func testCancellationWritesTypeCode381AndReference() throws {
        var invoice = SampleInvoice.make()
        XCTAssertFalse(invoice.isCancellation)
        XCTAssertTrue(try CIIWriter().xml(for: invoice, profile: .zugferdEN16931).contains("<ram:TypeCode>380</ram:TypeCode>"))
        XCTAssertFalse(try CIIWriter().xml(for: invoice, profile: .zugferdEN16931).contains("InvoiceReferencedDocument"))

        invoice.cancelsNumber = "RE-1"
        invoice.cancelsDate = invoice.issueDate
        let xml = try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
        XCTAssertTrue(xml.contains("<ram:TypeCode>381</ram:TypeCode>"))
        XCTAssertTrue(xml.contains("<ram:IssuerAssignedID>RE-1</ram:IssuerAssignedID>"))
        XCTAssertTrue(xml.contains("<ram:FormattedIssueDateTime>"))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
        // Positive Beträge, Verweis steht nach der Summenbildung
        XCTAssertTrue(xml.contains("<ram:DuePayableAmount>1904.00</ram:DuePayableAmount>"))
        let summation = xml.range(of: "</ram:SpecifiedTradeSettlementHeaderMonetarySummation>")!
        XCTAssertLessThan(summation.upperBound, xml.range(of: "<ram:InvoiceReferencedDocument>")!.lowerBound)
    }

    func testXRechnungNeedsBuyerReference() {
        var invoice = SampleInvoice.make()
        invoice.buyerReference = nil
        XCTAssertThrowsError(try CIIWriter().xml(for: invoice, profile: .xrechnung))
        XCTAssertNoThrow(try CIIWriter().xml(for: invoice, profile: .zugferdEN16931))
    }

    func testXMLEscapesSpecialCharacters() throws {
        var invoice = SampleInvoice.make()
        invoice.items[0].name = "Entwicklung <A> & \"B\""
        let xml = try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
        XCTAssertTrue(xml.contains("Entwicklung &lt;A&gt; &amp; &quot;B&quot;"))
    }

    // MARK: - Packer

    /// Kleinstes gültiges PDF mit klassischer xref-Tabelle
    private func minimalPDF() -> Data {
        var d = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        func add(_ s: String) {
            offsets.append(d.count)
            d.append(Data(s.utf8))
        }
        add("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        add("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
        add("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n")
        let xrefPos = d.count
        var x = "xref\n0 4\n0000000000 65535 f \n"
        for o in offsets { x += "\(pad10(o)) 00000 n \n" }
        x += "trailer\n<< /Size 4 /Root 1 0 R /ID [<00112233445566778899AABBCCDDEEFF> <00112233445566778899AABBCCDDEEFF>] >>\nstartxref\n\(xrefPos)\n%%EOF\n"
        d.append(Data(x.utf8))
        return d
    }

    func testPackerAppendsIncrementalUpdate() throws {
        let original = minimalPDF()
        let xml = Data("<test/>".utf8)
        let options = PDFA3Packer.Options(title: "Test", author: "Autor", iccProfile: Data(repeating: 0, count: 16))
        let packed = try PDFA3Packer().pack(pdf: original, xml: xml, options: options)

        XCTAssertTrue(packed.starts(with: original), "Original muss unverändert am Anfang stehen")
        let text = String(decoding: packed, as: UTF8.self)
        XCTAssertTrue(text.contains("/AFRelationship /Alternative"))
        XCTAssertTrue(text.contains("/Type /EmbeddedFile"))
        XCTAssertTrue(text.contains("/Subtype /text#2Fxml"))
        XCTAssertTrue(text.contains("/OutputIntents"))
        XCTAssertTrue(text.contains("<pdfaid:part>3</pdfaid:part>"))
        XCTAssertTrue(text.contains("<pdfaid:conformance>U</pdfaid:conformance>"))
        XCTAssertTrue(text.contains("/Pages 2 0 R"), "Alte Katalogeinträge müssen erhalten bleiben")
        XCTAssertEqual(text.components(separatedBy: "%%EOF").count - 1, 2)

        // Letzte startxref-Angabe zeigt auf eine xref-Tabelle
        let bytes = [UInt8](packed)
        let marker = Array("startxref\n".utf8)
        var pos = bytes.count - marker.count
        while pos >= 0, Array(bytes[pos..<(pos + marker.count)]) != marker { pos -= 1 }
        XCTAssertGreaterThanOrEqual(pos, 0)
        let tail = String(decoding: bytes[(pos + marker.count)...], as: UTF8.self)
        let offset = Int(tail.split(separator: "\n").first ?? "") ?? -1
        XCTAssertEqual(String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self), "xref")

        // Das gepackte PDF lässt sich ein zweites Mal nicht packen (/Prev), aber der Fehler ist klar
        XCTAssertThrowsError(try PDFA3Packer().pack(pdf: packed, xml: xml, options: options))
    }

    func testPackerRejectsPDFWithoutClassicXref() {
        let pdf = Data("%PDF-1.5\n1 0 obj\n<< >>\nendobj\nstartxref\n9\n%%EOF\n".utf8)
        let options = PDFA3Packer.Options(title: "T", author: "A", iccProfile: Data())
        XCTAssertThrowsError(try PDFA3Packer().pack(pdf: pdf, xml: Data(), options: options))
    }

    func testPDFStringEncoding() {
        let packer = PDFA3Packer()
        XCTAssertEqual(packer.pdfString("a(b)\\c"), "(a\\(b\\)\\\\c)")
        XCTAssertEqual(packer.pdfString("Ä"), "<FEFF00C4>")
    }
}
