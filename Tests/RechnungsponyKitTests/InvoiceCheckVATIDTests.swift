import XCTest
@testable import RechnungsponyKit

/// Die Prüfung der USt-IdNr. selbst steht in `VATIDCheck`; hier geht es um ihre Wirkung in der Rechnungsprüfung.
final class InvoiceCheckVATIDTests: XCTestCase {
    func testInvoiceCheckUsesIt() {
        var invoice = SampleInvoice.make()
        invoice.buyer.vatID = "DE123456789"
        XCTAssertTrue(InvoiceCheck.issues(for: invoice).contains { $0.severity == .warning && $0.message.hasPrefix("Kunde: Die Prüfziffer") })
        invoice.buyer.vatID = "DE12345"
        XCTAssertTrue(InvoiceCheck.issues(for: invoice).contains { $0.severity == .error && $0.message.hasPrefix("Kunde: Die USt-IdNr.") })
        invoice.buyer.vatID = "DE136695976"
        XCTAssertFalse(InvoiceCheck.issues(for: invoice).contains { $0.message.hasPrefix("Kunde:") && $0.message.contains("USt-IdNr.") })
    }
}
