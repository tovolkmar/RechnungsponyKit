import Foundation

/// Ein Befund der Prüfung vor dem Ausstellen.
public struct InvoiceIssue: Equatable, Identifiable, Sendable {
    public enum Severity: Sendable { case error, warning }

    public let severity: Severity
    public let message: String
    public var id: String { "\(severity)-\(message)" }

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Prüft eine Rechnung auf Lücken, bevor die Nummer vergeben wird.
/// Fehler würden im Validator scheitern oder eine unbrauchbare Rechnung ergeben,
/// Hinweise sind Auffälligkeiten, die man bewusst bestätigen kann.
public enum InvoiceCheck {
    public static func issues(
        for invoice: Invoice,
        isReceivedCredit: Bool = false,
        today: Date = Date.now,
        calendar: Calendar = .current
    ) -> [InvoiceIssue] {
        var out: [InvoiceIssue] = []
        func error(_ m: String) { out.append(InvoiceIssue(.error, m)) }
        func warn(_ m: String) { out.append(InvoiceIssue(.warning, m)) }

        // Absender und Bankdaten gehören bei einer erfassten Gutschrift des Kunden nicht dazu.
        if !isReceivedCredit {
            let s = invoice.seller
            if blank(s.name) { error("Absender: Name fehlt.") }
            if blank(s.street) || blank(s.postalCode) || blank(s.city) { error("Absender: Die Anschrift ist unvollständig.") }
            if !looksLikeEmail(s.email) { error("Absender: Es fehlt eine gültige E-Mail-Adresse (wird als elektronische Adresse benötigt).") }
            if blank(s.vatID) && blank(s.taxNumber) { error("Absender: USt-IdNr. oder Steuernummer fehlt.") }
            switch VATIDCheck.check(s.vatID ?? "") {
            case .invalidFormat: error("Absender: Die USt-IdNr. hat nicht das Format DE plus 9 Ziffern.")
            case .invalidChecksum: warn("Absender: Die Prüfziffer der USt-IdNr. stimmt nicht, vermutlich ein Tippfehler.")
            default: break
            }
            if blank(invoice.iban) {
                error("Bankverbindung: IBAN fehlt.")
            } else if !isValidIBAN(invoice.iban) {
                error("Bankverbindung: Die IBAN ist ungültig (Prüfziffer stimmt nicht).")
            }
            if let debit = invoice.directDebit {
                if blank(debit.debtorIBAN) {
                    error("Lastschrift: Die IBAN des Kunden fehlt.")
                } else if !isValidIBAN(debit.debtorIBAN) {
                    error("Lastschrift: Die IBAN des Kunden ist ungültig (Prüfziffer stimmt nicht).")
                }
                if blank(debit.mandateID) { error("Lastschrift: Die Mandatsreferenz fehlt.") }
                if blank(debit.creditorID) { error("Lastschrift: Die Gläubiger-ID fehlt (in den Absenderdaten eintragen).") }
            }

            let b = invoice.buyer
            if blank(b.name) { error("Kunde: Name fehlt.") }
            if blank(b.street) || blank(b.postalCode) || blank(b.city) { error("Kunde: Die Anschrift ist unvollständig.") }
            if b.countryCode.trimmingCharacters(in: .whitespaces).count != 2 { error("Kunde: Der Ländercode muss zwei Buchstaben haben, z. B. DE.") }
            if !looksLikeEmail(b.electronicAddress ?? "") && !looksLikeEmail(b.email) {
                error("Kunde: Es fehlt eine gültige E-Mail-Adresse (wird als elektronische Adresse benötigt).")
            }
            switch VATIDCheck.check(b.vatID ?? "") {
            case .invalidFormat: error("Kunde: Die USt-IdNr. hat nicht das Format DE plus 9 Ziffern (oder das Länderkürzel fehlt).")
            case .invalidChecksum: warn("Kunde: Die Prüfziffer der USt-IdNr. stimmt nicht, vermutlich ein Tippfehler.")
            default: break
            }
            if b.countryCode.uppercased() == "DE", !blank(b.postalCode), b.postalCode.count != 5 {
                warn("Kunde: Die Postleitzahl hat keine 5 Stellen.")
            }

            // BG-13: Der Ländercode der Lieferanschrift ist Pflicht (BT-80)
            if let ship = invoice.shipTo?.orNil {
                if ship.countryCode.trimmingCharacters(in: .whitespaces).count != 2 {
                    error("Lieferadresse: Der Ländercode muss zwei Buchstaben haben, z. B. DE.")
                }
            } else if let ship = invoice.shipTo, !blank(ship.name) {
                warn("Lieferadresse: Ohne Straße, PLZ oder Ort wird sie nicht in die Rechnung übernommen.")
            }
        }

        // Positionen
        if invoice.items.isEmpty { error("Es gibt keine Positionen.") }
        for (index, item) in invoice.items.enumerated() {
            let label = "Position \(index + 1)"
            if blank(item.name) { error("\(label): Bezeichnung fehlt.") }
            if item.quantity == 0 { error("\(label): Die Menge ist 0.") }
            else if item.quantity < 0 { warn("\(label): Die Menge ist negativ.") }
            if item.unitPrice == 0 { warn("\(label): Der Preis ist 0.") }
            switch item.taxCategory {
            case .standard:
                // Kategorie „S“ verlangt einen Satz über 0 %
                if item.vatRate <= 0 {
                    error("\(label): Ein Steuersatz von 0 % braucht die Kategorie „Steuerfrei“ oder „0 %“.")
                } else if item.vatRate != 19 && item.vatRate != 7 {
                    warn("\(label): Ungewöhnlicher Steuersatz (\(item.vatRate) %).")
                }
            case .exempt:
                if item.trimmedExemptionReason == nil { error("\(label): Der Befreiungsgrund für die Steuerfreiheit fehlt.") }
            case .zeroRated:
                break
            }
        }
        if !invoice.items.isEmpty {
            if invoice.grossTotal < 0 { warn("Der Gesamtbetrag ist negativ.") }
            else if invoice.grossTotal == 0 { warn("Der Gesamtbetrag ist 0.") }
        }

        // Daten
        let start = calendar.startOfDay(for: invoice.serviceStart)
        let end = calendar.startOfDay(for: invoice.serviceEnd)
        let issued = calendar.startOfDay(for: invoice.issueDate)
        let due = calendar.startOfDay(for: invoice.dueDate)
        if end < start { error("Der Leistungszeitraum endet vor seinem Beginn.") }
        for (index, item) in invoice.items.enumerated() {
            let label = "Position \(index + 1)"
            if (item.periodStart == nil) != (item.periodEnd == nil) {
                error("\(label): Der Leistungszeitraum braucht Beginn und Ende.")
            } else if let period = item.period {
                let itemStart = calendar.startOfDay(for: period.start)
                let itemEnd = calendar.startOfDay(for: period.end)
                if itemEnd < itemStart {
                    error("\(label): Der Leistungszeitraum endet vor seinem Beginn.")
                } else if itemStart < start || itemEnd > end {
                    warn("\(label): Der Leistungszeitraum liegt nicht innerhalb des Leistungszeitraums der Rechnung.")
                }
            }
        }
        if due < issued { warn(isReceivedCredit ? "Das Fälligkeitsdatum liegt vor dem Datum der Gutschrift." : "Das Zahlungsziel liegt vor dem Rechnungsdatum.") }
        if !isReceivedCredit, issued > calendar.startOfDay(for: today) {
            warn("Das Rechnungsdatum liegt in der Zukunft.")
        }
        return out
    }

    // MARK: Hilfen

    private static func blank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func looksLikeEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let domain = t[t.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !t.contains(" ")
    }

    /// IBAN-Prüfziffer nach ISO 13616 (Modulo 97).
    static func isValidIBAN(_ raw: String) -> Bool {
        let iban = raw.filter { !$0.isWhitespace }.uppercased()
        guard (15...34).contains(iban.count), iban.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        if iban.hasPrefix("DE"), iban.count != 22 { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for ch in rearranged {
            if let digit = ch.wholeNumberValue, ch.isNumber {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = ch.asciiValue {
                let value = Int(ascii) - 55 // A = 10 … Z = 35
                remainder = (remainder * 100 + value) % 97
            }
        }
        return remainder == 1
    }
}
