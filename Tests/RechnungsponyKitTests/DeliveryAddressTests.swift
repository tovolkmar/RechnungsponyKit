import XCTest
import Foundation
@testable import RechnungsponyKit

final class DeliveryAddressTests: XCTestCase {
    private func xml(_ shipTo: DeliveryAddress?) throws -> String {
        var invoice = SampleInvoice.make()
        invoice.shipTo = shipTo
        return try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)
    }

    func testWritesShipToTradePartyBeforeDeliveryEvent() throws {
        let text = try xml(DeliveryAddress(name: "Lager Süd", street: "Weg 2", postalCode: "80331", city: "München", countryCode: "DE"))
        let shipTo = try XCTUnwrap(text.range(of: "<ram:ShipToTradeParty>"))
        let event = try XCTUnwrap(text.range(of: "<ram:ActualDeliverySupplyChainEvent>"))
        XCTAssertLessThan(shipTo.lowerBound, event.lowerBound)
        XCTAssertTrue(text.contains("<ram:Name>Lager Süd</ram:Name>"))
        XCTAssertTrue(text.contains("<ram:LineOne>Weg 2</ram:LineOne>"))
        XCTAssertTrue(text.contains("<ram:CityName>München</ram:CityName>"))
        // ShipToTradeParty gehört in die Lieferung, nicht in die Vereinbarung
        let delivery = try XCTUnwrap(text.range(of: "<ram:ApplicableHeaderTradeDelivery>"))
        XCTAssertLessThan(delivery.lowerBound, shipTo.lowerBound)
    }

    func testWritesNothingWithoutDeliveryAddress() throws {
        XCTAssertFalse(try xml(nil).contains("ShipToTradeParty"))
    }

    func testOnlyCountryOrNameDoesNotCountAsAddress() throws {
        XCTAssertNil(DeliveryAddress(name: "Nur Name").orNil)
        XCTAssertFalse(try xml(DeliveryAddress(name: "Nur Name")).contains("ShipToTradeParty"))
        // Der Initialisierer von Invoice verwirft solche leeren Anschriften schon
        var invoice = SampleInvoice.make()
        invoice = Invoice(number: invoice.number, issueDate: invoice.issueDate, serviceStart: invoice.serviceStart, serviceEnd: invoice.serviceEnd,
                          dueDate: invoice.dueDate, seller: invoice.seller, buyer: invoice.buyer, shipTo: DeliveryAddress(),
                          iban: invoice.iban, items: invoice.items, paymentTerms: invoice.paymentTerms)
        XCTAssertNil(invoice.shipTo)
    }

    func testNameIsOptional() throws {
        let text = try xml(DeliveryAddress(street: "Weg 2", postalCode: "80331", city: "München"))
        let block = try XCTUnwrap(text.range(of: "<ram:ShipToTradeParty>"))
        let end = try XCTUnwrap(text.range(of: "</ram:ShipToTradeParty>"))
        XCTAssertFalse(text[block.lowerBound..<end.upperBound].contains("<ram:Name>"))
    }

    func testOldStoredInvoiceWithoutShipToStillDecodes() throws {
        var invoice = SampleInvoice.make()
        invoice.shipTo = nil
        let data = try JSONEncoder().encode(invoice)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("shipTo"))
        XCTAssertNil(try JSONDecoder().decode(Invoice.self, from: data).shipTo)
    }

    func testPDFRendersWithDeliveryAddress() throws {
        var invoice = SampleInvoice.make()
        invoice.shipTo = DeliveryAddress(name: "Lager Süd", street: "Weg 2", postalCode: "80331", city: "München")
        XCTAssertGreaterThan(try InvoicePDFRenderer().render(invoice).count, 1000)
    }

    func testCheckFlagsDeliveryAddressWithoutCountry() {
        var invoice = SampleInvoice.make()
        invoice.shipTo = DeliveryAddress(name: "Lager", street: "Weg 2", postalCode: "80331", city: "München", countryCode: "")
        let issues = InvoiceCheck.issues(for: invoice)
        XCTAssertTrue(issues.contains { $0.message.contains("Lieferadresse") && $0.severity == .error })
    }
}
