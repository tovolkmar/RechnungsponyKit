import XCTest
import Foundation
@testable import RechnungsponyKit

/// Die Leitweg-ID-Prüfung selbst steht in `LeitwegID`; hier geht es um ihre Wirkung auf Profil und Rechnungsprüfung.
final class XRechnungProfileTests: XCTestCase {
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
