import Testing
@testable import RechnungsponyKit

struct EmailCheckTests {
    @Test(arguments: ["info@muster.example", "rechnung@muster.de", " a@b.co ", "vor.name+tag@sub.domain.de"])
    func validAddresses(address: String) {
        #expect(EmailCheck.check(address) == .valid)
        #expect(EmailCheck.looksValid(address))
    }

    @Test(arguments: ["info", "info@", "@muster.de", "info@muster", "info@muster.", "in fo@muster.de", "info@mus ter.de"])
    func invalidAddresses(address: String) {
        #expect(EmailCheck.check(address) == .invalid)
        #expect(!EmailCheck.looksValid(address))
    }

    @Test func emptyInput() {
        #expect(EmailCheck.check("") == .empty)
        #expect(EmailCheck.check("   ") == .empty)
        #expect(!EmailCheck.looksValid(""))
    }
}
