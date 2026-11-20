import Testing
@testable import RechnungsponyKit

struct LeitwegIDTests {
    @Test(arguments: ["991-03730-19", "04011000-1234512345-06", " 04011000-1234512345-06 "])
    func validIDs(id: String) {
        #expect(LeitwegID.isValid(id))
    }

    @Test func wrongCheckDigitStillLooksLikeALeitwegID() {
        #expect(LeitwegID.looksLike("04011000-1234512345-35"))
        #expect(!LeitwegID.isValid("04011000-1234512345-35"))
    }

    @Test(arguments: ["", "2026-01-15", "PO-4711", "1-03730-19", "99", "BESTELLUNG 17", "17-04011000-06"])
    func otherReferencesAreNotTreatedAsLeitwegID(reference: String) {
        #expect(!LeitwegID.looksLike(reference), "\(reference)")
    }

    @Test func lettersInFineAddressingCountAsNumbers() {
        // 10 bis 35 für A bis Z; die Prüfziffer ergibt sich aus 98 − (Zahl · 100 mod 97)
        var number = ""
        for character in "04011000AB12" {
            number += character.isNumber ? String(character) : String(Int(character.asciiValue ?? 55) - 55)
        }
        var remainder = 0
        for digit in number { remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97 }
        let check = 98 - (remainder * 100) % 97
        let id = "04011000-AB12-" + (check < 10 ? "0\(check)" : "\(check)")
        #expect(LeitwegID.isValid(id), "\(id)")
    }
}
