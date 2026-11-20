import Testing
@testable import RechnungsponyKit

struct IBANCheckTests {
    @Test(arguments: [
        "DE02120300000000202051",
        "DE89370400440532013000",
        "GB82WEST12345698765432",
        "AT611904300234573201",
        "NL91ABNA0417164300",
        "FR1420041010050500013M02606"
    ])
    func validIBANs(iban: String) {
        #expect(IBANCheck.check(iban) == .valid)
        #expect(IBANCheck.isValid(iban))
    }

    @Test func spacesAndCaseAreIgnored() {
        #expect(IBANCheck.check("de02 1203 0000 0000 2020 51") == .valid)
        #expect(IBANCheck.check("  DE89 3704 0044 0532 0130 00  ") == .valid)
        #expect(IBANCheck.normalize(" de89 3704 ") == "DE893704")
    }

    @Test(arguments: [
        "DE02120300000000202052",  // letzte Ziffer falsch
        "DE89370400440532013001",
        "GB82WEST12345698765431"
    ])
    func checksumMismatch(iban: String) {
        #expect(IBANCheck.check(iban) == .invalidChecksum)
        #expect(!IBANCheck.isValid(iban))
    }

    @Test(arguments: [
        "DE0212030000000020205",   // deutsche IBAN mit 21 statt 22 Stellen
        "DE021203000000002020511", // 23 Stellen
        "DE02 1203 0000 0000 20X0 51",
        "1202DE0000000020205112",  // Länderkürzel fehlt
        "DEAB120300000000202051",  // Prüfziffern keine Ziffern
        "DE02",
        "DE02-1203-0000-0000-2020-51"
    ])
    func wrongFormat(iban: String) {
        #expect(IBANCheck.check(iban) == .invalidFormat)
        #expect(!IBANCheck.isValid(iban))
    }

    @Test func emptyInput() {
        #expect(IBANCheck.check("") == .empty)
        #expect(IBANCheck.check("   ") == .empty)
        #expect(!IBANCheck.isValid(""))
    }

    @Test func tooLongIsRejected() {
        #expect(IBANCheck.check("GB82WEST1234569876543212345678901234") == .invalidFormat)
    }
}
