import Foundation

// MARK: - XML

enum XML {
    static func escape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Zahlen

extension Decimal {
    /// Kaufmännisch auf 2 Nachkommastellen runden (0,5 wird aufgerundet).
    func rounded2() -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}

func dec(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        preconditionFailure("Ungültige Dezimalzahl: \(string)")
    }
    return value
}

enum Format {
    private static func string(_ value: Decimal, minFraction: Int, maxFraction: Int, locale: Locale, grouping: Bool) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouping
        f.minimumFractionDigits = minFraction
        f.maximumFractionDigits = maxFraction
        f.roundingMode = .halfUp
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let german = Locale(identifier: "de_DE")

    /// "1520.00" für XML
    static func xmlAmount(_ v: Decimal) -> String {
        string(v, minFraction: 2, maxFraction: 2, locale: posix, grouping: false)
    }

    /// "16" oder "16.5" für XML
    static func xmlQuantity(_ v: Decimal) -> String {
        string(v, minFraction: 0, maxFraction: 4, locale: posix, grouping: false)
    }

    /// "19.00" für XML
    static func xmlPercent(_ v: Decimal) -> String {
        string(v, minFraction: 2, maxFraction: 2, locale: posix, grouping: false)
    }

    /// "1.520,00 €" für die PDF-Anzeige
    static func germanMoney(_ v: Decimal) -> String {
        string(v, minFraction: 2, maxFraction: 2, locale: german, grouping: true) + " €"
    }

    /// "1.520,00" ohne Währung
    static func germanAmount(_ v: Decimal) -> String {
        string(v, minFraction: 2, maxFraction: 2, locale: german, grouping: true)
    }

    /// "16" oder "16,5"
    static func germanQuantity(_ v: Decimal) -> String {
        string(v, minFraction: 0, maxFraction: 2, locale: german, grouping: true)
    }

    /// feste Zahl der Nachkommastellen, z. B. "124,0"
    static func germanFixed(_ v: Decimal, digits: Int) -> String {
        string(v, minFraction: digits, maxFraction: digits, locale: german, grouping: true)
    }

    /// "19" oder "7"
    static func germanPercent(_ v: Decimal) -> String {
        string(v, minFraction: 0, maxFraction: 2, locale: german, grouping: false)
    }
}

// MARK: - Datum

enum DateFmt {
    static let berlin: TimeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 3600)!
    static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    static func format(_ date: Date, _ pattern: String, timeZone: TimeZone = DateFmt.berlin) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "20261008" (UN/CEFACT Format 102)
    static func ymd(_ d: Date) -> String { format(d, "yyyyMMdd") }

    /// "08.10.2026"
    static func german(_ d: Date) -> String { format(d, "dd.MM.yyyy") }

    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - Bytes

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

func pad10(_ n: Int) -> String {
    let s = String(n)
    return String(repeating: "0", count: max(0, 10 - s.count)) + s
}
