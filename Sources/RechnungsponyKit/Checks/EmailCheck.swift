import Foundation

/// Grobe Prüfung einer E-Mail-Adresse: ein „@“ nicht am Anfang, dahinter eine Domain mit Punkt, keine Leerzeichen.
/// Sie fängt offensichtliche Tippfehler ab, prüft aber nicht, ob die Adresse existiert.
enum EmailCheck {
    enum Result: Equatable, Sendable {
        /// Leer
        case empty
        case valid
        case invalid
    }

    static func check(_ raw: String) -> Result {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .empty }
        return looksValid(text) ? .valid : .invalid
    }

    static func looksValid(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let at = text.firstIndex(of: "@"), at != text.startIndex else { return false }
        let domain = text[text.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !text.contains(" ")
    }
}
