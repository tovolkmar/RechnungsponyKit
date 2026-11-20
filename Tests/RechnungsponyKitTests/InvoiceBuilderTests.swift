import XCTest
@testable import RechnungsponyKit

final class InvoiceBuilderTests: XCTestCase {
    private let seller = Party(name: "Muster GmbH", street: "Beispielweg 1", postalCode: "80331", city: "München",
                               email: "rechnung@muster.example", vatID: "DE136695976")
    private let buyer = Party(name: "Kunde AG", street: "Hauptstraße 2", postalCode: "10115", city: "Berlin",
                              email: "buchhaltung@kunde.example")
    private let day = DateFmt.make(2026, 11, 20)

    private func complete() -> Invoice {
        Invoice(number: "RE-2026-0001", issueDate: day)
            .withSeller(seller)
            .withBuyer(buyer)
            .addingLine(name: "Beratung", quantity: 8, unit: .hour, unitPrice: 95, vatRate: 19)
            .withBankAccount(iban: "DE02 1203 0000 0000 2020 51", bic: "BYLADEM1001")
            .withPaymentTerms("Zahlbar innerhalb von 14 Tagen", dueInDays: 14)
    }

    func testBuildsXMLFromSeparateInformation() throws {
        let xml = try complete().xml()
        XCTAssertTrue(xml.contains("<ram:ID>RE-2026-0001</ram:ID>"))
        XCTAssertTrue(xml.contains("Muster GmbH"))
        XCTAssertTrue(xml.contains("Kunde AG"))
        XCTAssertTrue(xml.contains("<ram:LineTotalAmount>760.00</ram:LineTotalAmount>"))
        XCTAssertTrue(xml.contains("<ram:GrandTotalAmount>904.40</ram:GrandTotalAmount>"))
        XCTAssertTrue(xml.contains(EInvoiceProfile.zugferdEN16931.guidelineID))
    }

    func testSettersDoNotChangeTheOriginal() {
        let base = Invoice(number: "A", issueDate: day)
        _ = base.withSeller(seller).addingLine(name: "x", quantity: 1, unitPrice: 1)
        XCTAssertTrue(base.items.isEmpty)
        XCTAssertEqual(base.seller.name, "")
    }

    func testDueDateAndTermsFromDays() {
        let invoice = complete()
        XCTAssertEqual(invoice.paymentDueDays, 14)
        XCTAssertEqual(invoice.dueDate, DateFmt.make(2026, 12, 4))
    }

    func testLinesAreAppendedInOrder() {
        let invoice = complete().addingLine(name: "Reisekosten", quantity: 1, unit: .lumpSum, unitPrice: 80)
        XCTAssertEqual(invoice.items.map(\.name), ["Beratung", "Reisekosten"])
        XCTAssertEqual(invoice.items[0].unitCode, "HUR")
        XCTAssertEqual(invoice.items[1].unitCode, "LS")
        XCTAssertEqual(invoice.withLines([]).items.count, 0)
    }

    func testIncompleteInvoiceThrowsWithIssues() {
        XCTAssertThrowsError(try Invoice(number: "RE-1", issueDate: day).xml()) { error in
            guard let error = error as? InvoiceValidationError else { return XCTFail("falscher Fehler: \(error)") }
            XCTAssertTrue(error.errors.contains { $0.message.hasPrefix("Absender") })
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testValidationCanBeSkipped() throws {
        let xml = try complete().withBuyerReference(nil).xml(validate: false)
        XCTAssertFalse(xml.isEmpty)
    }

    func testLeitwegIDSelectsXRechnung() throws {
        var withContact = seller
        withContact.contactName = "Max Mustermann"
        withContact.contactPhone = "+49 89 1234567"
        let invoice = complete().withSeller(withContact).withBuyerReference("04011000-1234512345-06")
        XCTAssertEqual(invoice.preferredProfile, .xrechnung)
        // XRechnung verlangt Ansprechpartner und Telefon: ohne sie bricht xml() mit einer Liste ab
        XCTAssertThrowsError(try complete().withBuyerReference("04011000-1234512345-06").xml())
        XCTAssertTrue(try invoice.xml().contains(EInvoiceProfile.xrechnung.guidelineID))
        // ausdrücklich gewähltes Profil gewinnt
        XCTAssertTrue(try invoice.xml(profile: .zugferdEN16931).contains(EInvoiceProfile.zugferdEN16931.guidelineID))
    }

    func testTaxFreeLineNeedsReasonAndIsWritten() throws {
        let invoice = complete()
            .withLines([])
            .addingLine(name: "Lieferung", quantity: 1, unitPrice: 100, vatRate: 0, taxCategory: .exempt, exemptionReason: "§ 19 UStG")
        let xml = try invoice.xml()
        XCTAssertTrue(xml.contains("§ 19 UStG"))
        XCTAssertEqual(invoice.taxTotal, 0)
    }

    func testBuiltInvoiceRoundTripsThroughReader() throws {
        let source = complete()
            .withReferences(buyerOrder: "B-77", contract: "R-1")
            .withProject(id: "P1", name: "Projekt")
            .withNotes(["Danke"])
        let read = try EInvoiceReader().parse(xml: Data(try source.xml().utf8)).invoice
        XCTAssertEqual(read.number, source.number)
        XCTAssertEqual(read.items.count, 1)
        XCTAssertEqual(read.grossTotal, source.grossTotal)
        XCTAssertEqual(read.buyerOrderNumber, "B-77")
    }

    func testCancellationAndShipTo() throws {
        let invoice = complete()
            .cancelling(number: "RE-2026-0000", issuedOn: DateFmt.make(2026, 11, 1))
            .withShipTo(DeliveryAddress(name: "Lager", street: "Weg 3", postalCode: "20095", city: "Hamburg"))
        XCTAssertTrue(invoice.isCancellation)
        XCTAssertNotNil(invoice.shipTo)
        XCTAssertNil(invoice.withShipTo(DeliveryAddress()).shipTo)
        XCTAssertTrue(try invoice.xml().contains("381"))
    }

    func testEveryUnitHasCodeAndLabel() {
        for unit in [LineUnit.piece, .hour, .day, .month, .lumpSum, .custom(code: "KMT", label: "km")] {
            XCTAssertFalse(unit.code.isEmpty)
            XCTAssertFalse(unit.label.isEmpty)
        }
    }
}
