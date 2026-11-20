import Foundation

/// Leitweg-ID für Rechnungen an Behörden (BT-10): Grobadressierung (2 bis 12 Ziffern, beginnt mit der Kennzahl des
/// Bundeslandes bzw. des Bundes), optional Feinadressierung (bis zu 30 Ziffern oder Großbuchstaben) und eine
/// zweistellige Prüfziffer nach ISO 7064 (Mod 97-10), getrennt durch Bindestriche, z. B. `04011000-1234512345-06`.
enum LeitwegID {
    private static let states: Set<String> = [
        "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "15", "16", "99"
    ]

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Sieht die Angabe wie eine Leitweg-ID aus (Aufbau und Kennzahl des Landes)? Unabhängig von der Prüfziffer;
    /// so fällt auch eine vertippte ID auf, während eine beliebige Referenz wie „2026-01-15“ nicht als solche gilt.
    static func looksLike(_ text: String) -> Bool {
        let value = normalized(text)
        guard value.count >= 5, value.count <= 46,
              value.range(of: "^[0-9]{2,12}(-[0-9A-Z]{0,30})?-[0-9]{2}$", options: .regularExpression) != nil
        else { return false }
        return states.contains(String(value.prefix(2)))
    }

    /// Aufbau, Kennzahl und Prüfziffer stimmen
    static func isValid(_ text: String) -> Bool {
        looksLike(text) && checksum(of: normalized(text).replacing("-", with: ""))
    }

    /// Mod 97-10: Buchstaben zählen als 10 bis 35; die Zahl samt Prüfziffer muss bei Division durch 97 den Rest 1 lassen.
    private static func checksum(of value: String) -> Bool {
        var remainder = 0
        for character in value {
            guard let digit = character.base36Value else { return false }
            remainder = digit < 10 ? (remainder * 10 + digit) % 97 : (remainder * 100 + digit) % 97
        }
        return remainder == 1
    }
}

private extension Character {
    /// 0 bis 9 für Ziffern, 10 bis 35 für A bis Z
    var base36Value: Int? {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 48...57: return Int(scalar.value) - 48
        case 65...90: return Int(scalar.value) - 55
        default: return nil
        }
    }
}
