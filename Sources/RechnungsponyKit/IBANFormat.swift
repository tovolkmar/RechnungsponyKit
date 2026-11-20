import Foundation

public enum IBANFormat {
    /// Großbuchstaben, ohne Leerzeichen, damit IBANs verglichen werden können
    public static func normalize(_ iban: String) -> String {
        IBANCheck.normalize(iban)
    }

    /// Für Texte auf der Rechnung: Anfang und Ende, die Mitte verdeckt (z. B. „DE12 **** **** 3456“)
    public static func masked(_ iban: String) -> String {
        let compact = normalize(iban)
        guard compact.count > 8 else { return compact }
        return "\(compact.prefix(4)) **** **** \(compact.suffix(4))"
    }
}
