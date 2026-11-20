import XCTest
import Foundation
@testable import RechnungsponyKit

final class TaxCategoryTests: XCTestCase {
    private func item(_ name: String, price: String, rate: String = "19", category: TaxCategory = .standard,
                      reason: String? = nil) -> LineItem {
        LineItem(name: name, quantity: 1, unitCode: "C62", unitLabel: "Stk.", unitPrice: dec(price), vatRate: dec(rate),
                 taxCategory: category, exemptionReason: reason)
    }

    private func invoice(_ items: [LineItem]) -> Invoice {
        var invoice = SampleInvoice.make()
        invoice.items = items
        return invoice
    }

    func testExemptItemBuildsOwnBreakdownWithReasonAndNoTax() {
        let invoice = invoice([item("A", price: "100"), item("B", price: "50", rate: "0", category: .exempt, reason: "Steuerfrei nach § 4 Nr. 14 UStG")])
        XCTAssertEqual(invoice.vatBreakdown.count, 2)
        let exempt = try! XCTUnwrap(invoice.vatBreakdown.first { $0.category == .exempt })
        XCTAssertEqual(exempt.basis, dec("50"))
        XCTAssertEqual(exempt.tax, 0)
        XCTAssertEqual(exempt.exemptionReason, "Steuerfrei nach § 4 Nr. 14 UStG")
        XCTAssertEqual(invoice.taxTotal, dec("19"))
        XCTAssertEqual(invoice.grossTotal, dec("169"))
        XCTAssertEqual(invoice.exemptionNotes, ["Steuerfrei nach § 4 Nr. 14 UStG"])
    }

    func testRateOfExemptAndZeroRatedIsIgnored() {
        // Steht in `vatRate` noch 19, gilt für Steuerfrei und Nullsatz trotzdem 0 %
        let invoice = invoice([item("A", price: "100", rate: "19", category: .exempt, reason: "x"),
                               item("B", price: "100", rate: "19", category: .zeroRated)])
        XCTAssertEqual(invoice.taxTotal, 0)
        XCTAssertEqual(invoice.vatBreakdown.map(\.rate), [0, 0])
    }

    func testSameCategoryAndReasonShareOneBreakdown() {
        let invoice = invoice([item("A", price: "10", category: .exempt, reason: "Grund"), item("B", price: "5", category: .exempt, reason: " Grund ")])
        XCTAssertEqual(invoice.vatBreakdown.count, 1)
        XCTAssertEqual(invoice.vatBreakdown[0].basis, dec("15"))
    }

    func testXMLCarriesCategoryAndReason() throws {
        let invoice = invoice([item("A", price: "100"), item("B", price: "50", category: .exempt, reason: "Steuerfrei nach § 4 Nr. 14 UStG"),
                               item("C", price: "20", category: .zeroRated)])
        let xml = try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
        XCTAssertTrue(xml.contains("<ram:ExemptionReason>Steuerfrei nach § 4 Nr. 14 UStG</ram:ExemptionReason>"))
        XCTAssertTrue(xml.contains("<ram:CategoryCode>E</ram:CategoryCode>"))
        XCTAssertTrue(xml.contains("<ram:CategoryCode>Z</ram:CategoryCode>"))
        XCTAssertTrue(xml.contains("<ram:CategoryCode>S</ram:CategoryCode>"))
        // Der Grund steht nur einmal, in der Steuerzusammenfassung
        XCTAssertEqual(xml.components(separatedBy: "<ram:ExemptionReason>").count - 1, 1)
        // Reihenfolge nach CII: ExemptionReason liegt zwischen TypeCode und BasisAmount
        let tax = try XCTUnwrap(xml.range(of: "<ram:ExemptionReason>"))
        let type = try XCTUnwrap(xml.range(of: "<ram:TypeCode>VAT</ram:TypeCode>", options: .backwards, range: xml.startIndex..<tax.lowerBound))
        let basis = try XCTUnwrap(xml.range(of: "<ram:BasisAmount>", range: tax.upperBound..<xml.endIndex))
        XCTAssertLessThan(type.lowerBound, tax.lowerBound)
        XCTAssertLessThan(tax.lowerBound, basis.lowerBound)
    }

    func testStandardWithZeroRateIsRejected() {
        XCTAssertThrowsError(try CIIWriter().xml(for: invoice([item("A", price: "10", rate: "0")]), profile: .zugferdEN16931))
    }

    func testExemptWithoutReasonIsRejected() {
        XCTAssertThrowsError(try CIIWriter().xml(for: invoice([item("A", price: "10", category: .exempt, reason: "  ")]), profile: .zugferdEN16931))
        XCTAssertNoThrow(try CIIWriter().xml(for: invoice([item("A", price: "10", category: .zeroRated)]), profile: .zugferdEN16931))
    }

    func testOldJSONWithoutCategoryDecodesAsStandard() throws {
        let json = #"{"name":"A","quantity":1,"unitCode":"C62","unitLabel":"Stk.","unitPrice":10,"vatRate":19}"#
        let decoded = try JSONDecoder().decode(LineItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.taxCategory, .standard)
        XCTAssertNil(decoded.exemptionReason)
    }

    func testRoundTripKeepsCategory() throws {
        let original = item("A", price: "10", category: .exempt, reason: "Grund")
        let decoded = try JSONDecoder().decode(LineItem.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
