import XCTest
import Foundation
@testable import RechnungsponyKit

final class DirectDebitTests: XCTestCase {
    private let debit = DirectDebit(debtorIBAN: "DE89 3704 0044 0532 0130 00", mandateID: "MANDAT-1", creditorID: "DE98ZZZ09999999999")

    private func xml(_ debit: DirectDebit?) throws -> String {
        var invoice = SampleInvoice.make()
        invoice.directDebit = debit
        return try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
    }

    func testDirectDebitWritesMeans59WithPayerAccountAndMandate() throws {
        let text = try xml(debit)
        XCTAssertTrue(text.contains("<ram:TypeCode>59</ram:TypeCode>"))
        XCTAssertFalse(text.contains("<ram:TypeCode>58</ram:TypeCode>"))
        XCTAssertTrue(text.contains("<ram:PayerPartyDebtorFinancialAccount>"))
        XCTAssertTrue(text.contains("<ram:IBANID>DE89370400440532013000</ram:IBANID>"))
        XCTAssertFalse(text.contains("PayeePartyCreditorFinancialAccount"))
        XCTAssertTrue(text.contains("<ram:CreditorReferenceID>DE98ZZZ09999999999</ram:CreditorReferenceID>"))
        XCTAssertTrue(text.contains("<ram:DirectDebitMandateID>MANDAT-1</ram:DirectDebitMandateID>"))
    }

    func testElementOrderFollowsCII() throws {
        let text = try xml(debit)
        func pos(_ s: String) throws -> String.Index { try XCTUnwrap(text.range(of: s)).lowerBound }
        // Kopf der Abrechnung: Gläubiger-ID, Verwendungszweck, Währung, Zahlungsart
        XCTAssertLessThan(try pos("<ram:CreditorReferenceID>"), try pos("<ram:PaymentReference>"))
        XCTAssertLessThan(try pos("<ram:PaymentReference>"), try pos("<ram:InvoiceCurrencyCode>"))
        XCTAssertLessThan(try pos("<ram:InvoiceCurrencyCode>"), try pos("<ram:SpecifiedTradeSettlementPaymentMeans>"))
        // Zahlungsbedingungen: Fälligkeit vor dem Mandat
        XCTAssertLessThan(try pos("<ram:DueDateDateTime>"), try pos("<ram:DirectDebitMandateID>"))
    }

    func testTransferKeepsMeans58AndPayeeAccount() throws {
        let text = try xml(nil)
        XCTAssertTrue(text.contains("<ram:TypeCode>58</ram:TypeCode>"))
        XCTAssertTrue(text.contains("PayeePartyCreditorFinancialAccount"))
        XCTAssertFalse(text.contains("DirectDebitMandateID"))
        XCTAssertFalse(text.contains("CreditorReferenceID"))
    }

    func testWriterRejectsIncompleteDirectDebit() {
        for incomplete in [DirectDebit(debtorIBAN: "", mandateID: "M", creditorID: "G"),
                           DirectDebit(debtorIBAN: "DE89370400440532013000", mandateID: " ", creditorID: "G"),
                           DirectDebit(debtorIBAN: "DE89370400440532013000", mandateID: "M", creditorID: "")] {
            XCTAssertThrowsError(try xml(incomplete))
        }
    }

    func testCheckReportsMissingAndInvalidDirectDebitData() {
        var invoice = SampleInvoice.make()
        invoice.directDebit = DirectDebit(debtorIBAN: "DE00 1234", mandateID: "", creditorID: "")
        let messages = InvoiceCheck.issues(for: invoice).filter { $0.severity == .error }.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("IBAN des Kunden ist ungültig") })
        XCTAssertTrue(messages.contains { $0.contains("Mandatsreferenz") })
        XCTAssertTrue(messages.contains { $0.contains("Gläubiger-ID") })
        invoice.directDebit = debit
        XCTAssertFalse(InvoiceCheck.issues(for: invoice).contains { $0.message.hasPrefix("Lastschrift") })
    }

    func testReaderTakesDirectDebitFromXML() throws {
        let read = try EInvoiceReader().parse(xml: Data(try xml(debit).utf8)).invoice
        XCTAssertEqual(read.directDebit, DirectDebit(debtorIBAN: "DE89370400440532013000", mandateID: "MANDAT-1", creditorID: "DE98ZZZ09999999999"))
        XCTAssertNil(try EInvoiceReader().parse(xml: Data(try xml(nil).utf8)).invoice.directDebit)
    }

    func testOldStoredInvoiceWithoutDirectDebitDecodes() throws {
        let data = try JSONEncoder().encode(SampleInvoice.make())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("directDebit"))
        XCTAssertNil(try JSONDecoder().decode(Invoice.self, from: data).directDebit)
    }

    func testMaskedIBANHidesTheMiddle() {
        XCTAssertEqual(IBANFormat.masked("DE89 3704 0044 0532 0130 00"), "DE89 **** **** 3000")
        XCTAssertEqual(IBANFormat.masked("DE12"), "DE12")
    }
}
