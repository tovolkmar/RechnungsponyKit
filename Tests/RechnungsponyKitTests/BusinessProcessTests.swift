import XCTest
import Foundation
@testable import RechnungsponyKit

final class BusinessProcessTests: XCTestCase {
    private let process = "<ram:BusinessProcessSpecifiedDocumentContextParameter>"

    func testXRechnungWritesBusinessProcessBeforeGuideline() throws {
        let text = try CIIWriter().xml(for: SampleInvoice.make(), profile: .xrechnung)
        let business = try XCTUnwrap(text.range(of: process))
        let guideline = try XCTUnwrap(text.range(of: "<ram:GuidelineSpecifiedDocumentContextParameter>"))
        XCTAssertLessThan(business.lowerBound, guideline.lowerBound)
        XCTAssertTrue(text.contains("<ram:ID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</ram:ID>"))
    }

    func testZUGFeRDStaysWithoutBusinessProcess() throws {
        let text = try CIIWriter().xml(for: SampleInvoice.make(), profile: .zugferdEN16931)
        XCTAssertFalse(text.contains(process))
    }
}
