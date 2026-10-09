import XCTest
@testable import InvoiceKit

final class InvoiceCheckTests: XCTestCase {
    private let today = DateFmt.make(2026, 10, 9)

    private func errors(_ invoice: Invoice, credit: Bool = false) -> [String] {
        InvoiceCheck.issues(for: invoice, isReceivedCredit: credit, today: today).filter { $0.severity == .error }.map(\.message)
    }

    private func warnings(_ invoice: Invoice) -> [String] {
        InvoiceCheck.issues(for: invoice, today: today).filter { $0.severity == .warning }.map(\.message)
    }

    func testSampleInvoiceIsClean() {
        XCTAssertEqual(InvoiceCheck.issues(for: SampleInvoice.make(), today: today), [])
    }

    func testIBANValidation() {
        XCTAssertTrue(InvoiceCheck.isValidIBAN("DE02 1203 0000 0000 2020 51"))
        XCTAssertTrue(InvoiceCheck.isValidIBAN("GB82WEST12345698765432"))
        XCTAssertFalse(InvoiceCheck.isValidIBAN("DE02120300000000202052"))
        XCTAssertFalse(InvoiceCheck.isValidIBAN("DE0212030000000020205"))
        XCTAssertFalse(InvoiceCheck.isValidIBAN(""))
    }

    func testMissingMasterDataIsError() {
        var inv = SampleInvoice.make()
        inv.seller.vatID = nil
        inv.seller.email = ""
        inv.buyer.street = ""
        inv.iban = "DE00"
        let e = errors(inv)
        XCTAssertTrue(e.contains { $0.contains("USt-IdNr") })
        XCTAssertTrue(e.contains { $0.contains("Absender") && $0.contains("E-Mail") })
        XCTAssertTrue(e.contains { $0.contains("Kunde") && $0.contains("Anschrift") })
        XCTAssertTrue(e.contains { $0.contains("IBAN") })
    }

    func testTaxNumberReplacesVatID() {
        var inv = SampleInvoice.make()
        inv.seller.vatID = nil
        inv.seller.taxNumber = "123/456/78901"
        XCTAssertEqual(errors(inv), [])
    }

    func testZeroVatRateIsError() {
        var inv = SampleInvoice.make()
        inv.items[0].vatRate = 0
        XCTAssertTrue(errors(inv).contains { $0.contains("0 %") })
    }

    func testItemProblems() {
        var inv = SampleInvoice.make()
        inv.items[0].name = " "
        inv.items[1].quantity = 0
        let e = errors(inv)
        XCTAssertTrue(e.contains { $0.hasPrefix("Position 1") })
        XCTAssertTrue(e.contains { $0.hasPrefix("Position 2") })
        inv.items = []
        XCTAssertTrue(errors(inv).contains("Es gibt keine Positionen."))
    }

    func testDateChecks() {
        var inv = SampleInvoice.make()
        inv.serviceEnd = DateFmt.make(2026, 8, 1)
        XCTAssertTrue(errors(inv).contains { $0.contains("Leistungszeitraum") })

        inv = SampleInvoice.make()
        inv.dueDate = DateFmt.make(2026, 10, 1)
        inv.issueDate = DateFmt.make(2026, 10, 20)
        let w = warnings(inv)
        XCTAssertTrue(w.contains { $0.contains("Zahlungsziel") })
        XCTAssertTrue(w.contains { $0.contains("Zukunft") })
    }

    func testReceivedCreditSkipsSellerAndBankChecks() {
        var inv = SampleInvoice.make()
        inv.seller.vatID = nil
        inv.iban = ""
        inv.buyer.street = ""
        XCTAssertEqual(errors(inv, credit: true), [])
    }
}
