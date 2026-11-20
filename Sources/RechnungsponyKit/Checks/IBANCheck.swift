import Foundation

/// Offline-Prüfung einer IBAN: Aufbau (Länderkürzel, Prüfziffern, Länge) und Prüfsumme nach ISO 13616 (Modulo 97).
/// Sie fängt Tippfehler ab, bestätigt aber nicht, dass das Konto wirklich existiert.
enum IBANCheck {
    enum Result: Equatable, Sendable {
        /// Leer
        case empty
        /// Aufbau und Prüfsumme stimmen
        case valid
        /// Länge oder Zeichen passen nicht zu einer IBAN
        case invalidFormat
        /// Aufbau stimmt, Prüfsumme nicht, vermutlich ein Tippfehler
        case invalidChecksum
    }

    /// Großbuchstaben, ohne Leerzeichen
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace }
    }

    static func isValid(_ raw: String) -> Bool {
        check(raw) == .valid
    }

    static func check(_ raw: String) -> Result {
        let iban = normalize(raw)
        if iban.isEmpty { return .empty }
        let characters = Array(iban)
        guard (15...34).contains(characters.count),
              characters.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              characters[0].isLetter, characters[1].isLetter,
              characters[2].isNumber, characters[3].isNumber else { return .invalidFormat }
        // Deutsche IBANs haben genau 22 Stellen, nach dem Länderkürzel nur Ziffern
        if iban.hasPrefix("DE"), characters.count != 22 || !characters.dropFirst(2).allSatisfy(\.isNumber) {
            return .invalidFormat
        }
        return remainder(of: characters) == 1 ? .valid : .invalidChecksum
    }

    /// Rest der umgestellten IBAN (erste vier Stellen ans Ende, Buchstaben als 10 bis 35) geteilt durch 97
    private static func remainder(of characters: [Character]) -> Int {
        let rearranged = characters.dropFirst(4) + characters.prefix(4)
        var remainder = 0
        for character in rearranged {
            if let digit = character.wholeNumberValue, character.isNumber {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = character.asciiValue {
                remainder = (remainder * 100 + Int(ascii) - 55) % 97 // A = 10 … Z = 35
            }
        }
        return remainder
    }
}
