import XCTest
@testable import InvoiceKit

final class VATIDCheckTests: XCTestCase {
    func testValidGermanNumbers() {
        XCTAssertEqual(VATIDCheck.check("DE123456789"), .valid)
        XCTAssertEqual(VATIDCheck.check("DE123456789"), .valid)
        XCTAssertEqual(VATIDCheck.check("DE813123104"), .valid)
    }

    func testSeparatorsAndCaseAreIgnored() {
        XCTAssertEqual(VATIDCheck.check("de 136 695 976"), .valid)
        XCTAssertEqual(VATIDCheck.check("DE-136.695.976"), .valid)
    }

    func testChecksumMismatch() {
        XCTAssertEqual(VATIDCheck.check("DE123456789"), .invalidChecksum)
        XCTAssertEqual(VATIDCheck.check("DE136695977"), .invalidChecksum)
    }

    func testWrongFormat() {
        XCTAssertEqual(VATIDCheck.check("DE13669597"), .invalidFormat)
        XCTAssertEqual(VATIDCheck.check("DE1234567891"), .invalidFormat)
        XCTAssertEqual(VATIDCheck.check("DE036695976"), .invalidFormat)
        XCTAssertEqual(VATIDCheck.check("136695976"), .invalidFormat)
        XCTAssertEqual(VATIDCheck.check("DE13669597X"), .invalidFormat)
    }

    func testEmptyAndForeign() {
        XCTAssertEqual(VATIDCheck.check(""), .empty)
        XCTAssertEqual(VATIDCheck.check("  "), .empty)
        XCTAssertEqual(VATIDCheck.check("ATU12345678"), .foreign)
        XCTAssertEqual(VATIDCheck.check("FR12345678901"), .foreign)
    }

    func testInvoiceCheckUsesIt() {
        var invoice = SampleInvoice.make()
        invoice.buyer.vatID = "DE123456789"
        XCTAssertTrue(InvoiceCheck.issues(for: invoice).contains { $0.severity == .warning && $0.message.hasPrefix("Kunde: Die Prüfziffer") })
        invoice.buyer.vatID = "DE12345"
        XCTAssertTrue(InvoiceCheck.issues(for: invoice).contains { $0.severity == .error && $0.message.hasPrefix("Kunde: Die USt-IdNr.") })
        invoice.buyer.vatID = "DE123456789"
        XCTAssertFalse(InvoiceCheck.issues(for: invoice).contains { $0.message.contains("USt-IdNr.") })
    }
}
