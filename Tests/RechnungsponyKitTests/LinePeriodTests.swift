import XCTest
import Foundation
@testable import RechnungsponyKit

final class LinePeriodTests: XCTestCase {
    private func invoice(_ start: Date?, _ end: Date?) -> Invoice {
        var invoice = SampleInvoice.make()
        invoice.items[0].periodStart = start
        invoice.items[0].periodEnd = end
        return invoice
    }

    func testWritesLinePeriodAfterTaxAndBeforeLineTotal() throws {
        let text = try CIIWriter().xml(for: invoice(DateFmt.make(2026, 7, 1), DateFmt.make(2026, 7, 31)), profile: .zugferdEN16931)
        let tax = try XCTUnwrap(text.range(of: "<ram:RateApplicablePercent>"))
        let period = try XCTUnwrap(text.range(of: "<ram:BillingSpecifiedPeriod>"))
        let total = try XCTUnwrap(text.range(of: "<ram:SpecifiedTradeSettlementLineMonetarySummation>"))
        XCTAssertLessThan(tax.lowerBound, period.lowerBound)
        XCTAssertLessThan(period.lowerBound, total.lowerBound)
        XCTAssertTrue(text.contains("<udt:DateTimeString format=\"102\">20260701</udt:DateTimeString>"))
        XCTAssertTrue(text.contains("<udt:DateTimeString format=\"102\">20260731</udt:DateTimeString>"))
    }

    func testWritesNoLinePeriodWithoutOrWithHalfAPeriod() throws {
        // Der Rechnungskopf hat selbst einen Zeitraum; gezählt wird nur der in der Position
        let none = try CIIWriter().xml(for: invoice(nil, nil), profile: .zugferdEN16931)
        let half = try CIIWriter().xml(for: invoice(DateFmt.make(2026, 7, 1), nil), profile: .zugferdEN16931)
        XCTAssertEqual(none.components(separatedBy: "<ram:BillingSpecifiedPeriod>").count, 2)
        XCTAssertEqual(half.components(separatedBy: "<ram:BillingSpecifiedPeriod>").count, 2)
    }

    func testOldStoredItemWithoutPeriodDecodes() throws {
        let item = invoice(nil, nil).items[0]
        let data = try JSONEncoder().encode(item)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("periodStart"))
        XCTAssertNil(try JSONDecoder().decode(LineItem.self, from: data).period)
    }

    func testCheckFlagsReversedAndHalfPeriodsAndWarnsOutside() {
        let reversed = InvoiceCheck.issues(for: invoice(DateFmt.make(2026, 9, 20), DateFmt.make(2026, 9, 10)))
        XCTAssertTrue(reversed.contains { $0.severity == .error && $0.message.contains("Position 1") })
        let half = InvoiceCheck.issues(for: invoice(DateFmt.make(2026, 9, 1), nil))
        XCTAssertTrue(half.contains { $0.severity == .error && $0.message.contains("Beginn und Ende") })
        let outside = InvoiceCheck.issues(for: invoice(DateFmt.make(2026, 8, 1), DateFmt.make(2026, 8, 31)))
        XCTAssertTrue(outside.contains { $0.severity == .warning && $0.message.contains("Position 1") })
        let inside = InvoiceCheck.issues(for: invoice(DateFmt.make(2026, 9, 5), DateFmt.make(2026, 9, 20)))
        XCTAssertFalse(inside.contains { $0.message.contains("Position 1") })
    }

    func testReaderTakesLinePeriodFromXML() throws {
        var source = invoice(DateFmt.make(2026, 7, 1), DateFmt.make(2026, 7, 31))
        source.items[0].taxCategory = .standard
        let xml = try CIIWriter().xml(for: source, profile: .zugferdEN16931)
        let read = try EInvoiceReader().parse(xml: Data(xml.utf8)).invoice
        XCTAssertEqual(read.items[0].periodStart, DateFmt.make(2026, 7, 1))
        XCTAssertEqual(read.items[0].periodEnd, DateFmt.make(2026, 7, 31))
    }

    func testPDFRendersWithLinePeriod() throws {
        XCTAssertGreaterThan(try InvoicePDFRenderer().render(invoice(DateFmt.make(2026, 7, 1), DateFmt.make(2026, 7, 31))).count, 1000)
    }

    // MARK: Hinweis mit Betreffcode REG

    func testLegalNoteIsAlsoWrittenAsRegNote() throws {
        var invoice = SampleInvoice.make()
        invoice.seller.legalNote = "Registergericht Jena HRB 1"
        invoice.notes = ["Danke"]
        let text = try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
        XCTAssertTrue(text.contains("<ram:Content>Registergericht Jena HRB 1</ram:Content>\n      <ram:SubjectCode>REG</ram:SubjectCode>")
                      || text.contains("<ram:SubjectCode>REG</ram:SubjectCode>"))
        // BT-33 bleibt erhalten und der gewöhnliche Hinweis bekommt keinen Betreffcode
        XCTAssertTrue(text.contains("<ram:Description>Registergericht Jena HRB 1</ram:Description>"))
        XCTAssertEqual(text.components(separatedBy: "<ram:SubjectCode>").count, 2)
        // Zurückgelesen werden die Hinweise ohne die Registerangabe
        let read = try EInvoiceReader().parse(xml: Data(text.utf8)).invoice
        XCTAssertEqual(read.notes, ["Danke"])
        XCTAssertEqual(read.seller.legalNote, "Registergericht Jena HRB 1")
    }

    func testNoRegNoteWithoutLegalNote() throws {
        var invoice = SampleInvoice.make()
        invoice.seller.legalNote = nil
        XCTAssertFalse(try CIIWriter().xml(for: invoice, profile: .zugferdEN16931).contains("SubjectCode"))
    }
}
