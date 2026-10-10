import Foundation

/// Offline-Prüfung einer deutschen USt-IdNr.: Aufbau (DE + 9 Ziffern) und Prüfziffer.
/// Sie fängt Tippfehler ab, bestätigt aber nicht, dass die Nummer wirklich vergeben ist.
public enum VATIDCheck {
    public enum Result: Equatable, Sendable {
        /// Leer
        case empty
        /// Deutsche Nummer, Aufbau und Prüfziffer stimmen
        case valid
        /// Deutsche Nummer, aber nicht „DE“ plus 9 Ziffern (die erste nicht 0)
        case invalidFormat
        /// Aufbau stimmt, Prüfziffer nicht, vermutlich ein Tippfehler
        case invalidChecksum
        /// Nummer aus einem anderen Land: nicht geprüft
        case foreign
    }

    /// Entfernt Leerzeichen, Punkte, Bindestriche und macht Großbuchstaben
    public static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func check(_ raw: String) -> Result {
        let id = normalize(raw)
        if id.isEmpty { return .empty }
        guard id.hasPrefix("DE") else {
            // Beginnt mit zwei Buchstaben eines anderen Landes
            let prefix = id.prefix(2)
            return prefix.allSatisfy(\.isLetter) ? .foreign : .invalidFormat
        }
        let digits = id.dropFirst(2).compactMap { $0.wholeNumberValue }
        guard id.count == 11, digits.count == 9, digits[0] != 0 else { return .invalidFormat }
        return checksumMatches(digits) ? .valid : .invalidChecksum
    }

    /// Prüfziffer nach dem Verfahren der Bundesfinanzverwaltung (Modulo 11, Produkt 10)
    private static func checksumMatches(_ d: [Int]) -> Bool {
        var product = 10
        for digit in d.prefix(8) {
            var sum = (digit + product) % 10
            if sum == 0 { sum = 10 }
            product = (2 * sum) % 11
        }
        var check = 11 - product
        if check == 10 { check = 0 }
        return check == d[8]
    }
}
