import Testing
@testable import RechnungsponyKit

struct VATIDCheckTests {
    @Test(arguments: ["DE136695976"])
    func validGermanNumbers(number: String) {
        #expect(VATIDCheck.check(number) == .valid)
    }

    @Test(arguments: ["de 136 695 976", "DE-136.695.976", "  DE136695976  "])
    func separatorsAndCaseAreIgnored(number: String) {
        #expect(VATIDCheck.check(number) == .valid)
    }

    @Test(arguments: ["DE123456789", "DE136695977"])
    func checksumMismatch(number: String) {
        #expect(VATIDCheck.check(number) == .invalidChecksum)
    }

    @Test(arguments: [
        "DE13669597",    // eine Ziffer zu wenig
        "DE1366959761",  // eine Ziffer zu viel
        "DE036695976",   // beginnt mit 0
        "136695976",     // ohne Länderkennung
        "DE13669597X"    // Buchstabe statt Ziffer
    ])
    func wrongFormat(number: String) {
        #expect(VATIDCheck.check(number) == .invalidFormat)
    }

    @Test func emptyAndForeign() {
        #expect(VATIDCheck.check("") == .empty)
        #expect(VATIDCheck.check("  ") == .empty)
        #expect(VATIDCheck.check("ATU12345678") == .foreign)
        #expect(VATIDCheck.check("FR12345678901") == .foreign)
    }

    @Test func normalizeKeepsOnlyLettersAndDigits() {
        #expect(VATIDCheck.normalize(" de 136.695-976 ") == "DE136695976")
    }
}
