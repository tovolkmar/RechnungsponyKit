import XCTest
import Foundation
@testable import InvoiceKit

final class LeitwegIDTests: XCTestCase {
    func testValidIDs() {
        XCTAssertTrue(LeitwegID.isValid("991-03730-19"))
        XCTAssertTrue(LeitwegID.isValid("04011000-1234512345-06"))
        XCTAssertTrue(LeitwegID.isValid(" 04011000-1234512345-06 "))
    }

    func testWrongCheckDigitStillLooksLikeALeitwegID() {
        XCTAssertTrue(LeitwegID.looksLike("04011000-1234512345-35"))
        XCTAssertFalse(LeitwegID.isValid("04011000-1234512345-35"))
    }

    func testOtherReferencesAreNotTreatedAsLeitwegID() {
        for reference in ["", "2026-01-15", "PO-4711", "1-03730-19", "99", "BESTELLUNG 17", "17-04011000-06"] {
            XCTAssertFalse(LeitwegID.looksLike(reference), reference)
        }
    }

    func testLettersInFineAddressingCountAsNumbers() {
        // 10 bis 35 für A bis Z; die Prüfziffer ergibt sich aus 98 − (Zahl · 100 mod 97)
        let base = "04011000AB12"
        var number = ""
        for c in base { number += c.isNumber ? String(c) : String(Int(c.asciiValue!) - 55) }
        var remainder = 0
        for digit in number { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        let check = 98 - (remainder * 100) % 97
        let id = "04011000-AB12-" + (check < 10 ? "0\(check)" : "\(check)")
        XCTAssertTrue(LeitwegID.isValid(id), id)
    }

    func testPreferredProfileFollowsTheBuyerReference() {
        var invoice = SampleInvoice.make()
        invoice.buyerReference = "04011000-1234512345-06"
        XCTAssertEqual(invoice.preferredProfile, .xrechnung)
        invoice.buyerReference = "PO-4711"
        XCTAssertEqual(invoice.preferredProfile, .zugferdEN16931)
        invoice.buyerReference = nil
        XCTAssertEqual(invoice.preferredProfile, .zugferdEN16931)
    }

    func testCheckAsksForXRechnungDetailsAndTheCheckDigit() {
        var invoice = SampleInvoice.make()
        invoice.buyerReference = "04011000-1234512345-35"
        invoice.seller.contactName = nil
        invoice.seller.contactPhone = nil
        let messages = InvoiceCheck.issues(for: invoice).filter { $0.severity == .error }.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Prüfziffer") })
        XCTAssertTrue(messages.contains { $0.contains("Ansprechpartner") })
        XCTAssertTrue(messages.contains { $0.contains("Telefon") })

        invoice.buyerReference = "PO-4711"
        let normal = InvoiceCheck.issues(for: invoice).map(\.message)
        XCTAssertFalse(normal.contains { $0.contains("XRechnung") || $0.contains("Prüfziffer der Leitweg") })
    }
}
