import Foundation

/// Gängige Mengeneinheiten (UN/ECE Recommendation 20) für `Invoice.addingLine(…)`.
public enum LineUnit: Sendable, Equatable {
    case piece, hour, day, month, lumpSum
    /// Eigene Einheit: UN/ECE-Code und Anzeigetext
    case custom(code: String, label: String)

    public var code: String {
        switch self {
        case .piece: "C62"
        case .hour: "HUR"
        case .day: "DAY"
        case .month: "MON"
        case .lumpSum: "LS"
        case .custom(let code, _): code
        }
    }

    /// Text für die Anzeige im PDF
    public var label: String {
        switch self {
        case .piece: "Stk."
        case .hour: "Std."
        case .day: "Tag"
        case .month: "Mon."
        case .lumpSum: "pauschal"
        case .custom(_, let label): label
        }
    }
}

/// Wird geworfen, wenn eine Rechnung vor dem Schreiben des XML Fehler hat. `issues` enthält Fehler und Hinweise.
public struct InvoiceValidationError: Error, LocalizedError, Sendable {
    public let issues: [InvoiceIssue]

    public var errors: [InvoiceIssue] { issues.filter { $0.severity == .error } }

    public var errorDescription: String? {
        "Die Rechnung ist unvollständig oder fehlerhaft:\n" + errors.map { "• \($0.message)" }.joined(separator: "\n")
    }
}

// MARK: - Rechnung Schritt für Schritt aufbauen

/// Jede dieser Methoden liefert eine geänderte Kopie zurück (`Invoice` ist ein Werttyp). So lässt sich eine Rechnung
/// aus einzelnen Angaben zusammensetzen und am Ende als XML schreiben:
///
///     let xml = try Invoice(number: "RE-1", issueDate: date)
///         .withSeller(seller)
///         .withBuyer(buyer)
///         .addingLine(name: "Beratung", quantity: 8, unit: .hour, unitPrice: 95, vatRate: 19)
///         .withBankAccount(iban: "DE02 1203 0000 0000 2020 51")
///         .withPaymentTerms("Zahlbar innerhalb von 14 Tagen", dueInDays: 14)
///         .xml()
extension Invoice {
    /// Leere Rechnung mit Nummer und Datum. Leistungszeitraum und Fälligkeit sind zunächst das Rechnungsdatum;
    /// alles Weitere setzt du mit den `with…`-Methoden. Was noch fehlt, meldet `issues()` bzw. `xml()`.
    public init(number: String, issueDate: Date) {
        let empty = Party(name: "", street: "", postalCode: "", city: "", email: "")
        self.init(
            number: number, issueDate: issueDate, serviceStart: issueDate, serviceEnd: issueDate, dueDate: issueDate,
            seller: empty, buyer: empty, iban: "", items: [], paymentTerms: ""
        )
    }

    public func withNumber(_ number: String, issueDate: Date? = nil) -> Invoice {
        var copy = self
        copy.number = number
        if let issueDate { copy.issueDate = issueDate }
        return copy
    }

    /// Absender (Rechnungssteller)
    public func withSeller(_ seller: Party) -> Invoice {
        var copy = self
        copy.seller = seller
        return copy
    }

    /// Empfänger (Rechnungsempfänger)
    public func withBuyer(_ buyer: Party) -> Invoice {
        var copy = self
        copy.buyer = buyer
        return copy
    }

    /// Abweichende Lieferanschrift (BG-13); eine leere Anschrift entfernt sie wieder
    public func withShipTo(_ address: DeliveryAddress?) -> Invoice {
        var copy = self
        copy.shipTo = address?.orNil
        return copy
    }

    /// Käuferreferenz (BT-10); bei Behörden die Leitweg-ID (dann schreibt `xml()` ohne Profilangabe XRechnung)
    public func withBuyerReference(_ reference: String?) -> Invoice {
        var copy = self
        copy.buyerReference = reference
        return copy
    }

    /// Leistungszeitraum der Rechnung; ohne Ende ein einzelner Tag
    public func withServicePeriod(from start: Date, to end: Date? = nil) -> Invoice {
        var copy = self
        copy.serviceStart = start
        copy.serviceEnd = end ?? start
        return copy
    }

    /// Alle Positionen ersetzen
    public func withLines(_ lines: [LineItem]) -> Invoice {
        var copy = self
        copy.items = lines
        return copy
    }

    /// Eine Position anhängen
    public func addingLine(_ line: LineItem) -> Invoice {
        var copy = self
        copy.items.append(line)
        return copy
    }

    /// Eine Position anhängen, mit den gängigen Angaben. Der Steuersatz gilt für die Kategorie „mit Umsatzsteuer“;
    /// für Nullsatz oder steuerfrei gib `taxCategory` (und bei steuerfrei den Befreiungsgrund) an.
    public func addingLine(
        name: String,
        quantity: Decimal,
        unit: LineUnit = .piece,
        unitPrice: Decimal,
        vatRate: Decimal = 19,
        taxCategory: TaxCategory = .standard,
        exemptionReason: String? = nil,
        details: String? = nil,
        periodStart: Date? = nil,
        periodEnd: Date? = nil
    ) -> Invoice {
        addingLine(LineItem(
            name: name, quantity: quantity, unitCode: unit.code, unitLabel: unit.label, unitPrice: unitPrice,
            vatRate: vatRate, details: details, taxCategory: taxCategory, exemptionReason: exemptionReason,
            periodStart: periodStart, periodEnd: periodEnd
        ))
    }

    /// Bankverbindung für die Überweisung (Zahlungsart 58)
    public func withBankAccount(iban: String, bic: String? = nil, accountName: String? = nil) -> Invoice {
        var copy = self
        copy.iban = iban
        copy.bic = bic
        copy.accountName = accountName
        return copy
    }

    /// Zahlung per SEPA-Lastschrift (Zahlungsart 59) statt Überweisung
    public func withDirectDebit(_ debit: DirectDebit?) -> Invoice {
        var copy = self
        copy.directDebit = debit
        return copy
    }

    /// Zahlungsbedingungen als Text; mit `dueInDays` wird auch das Fälligkeitsdatum gesetzt (Rechnungsdatum plus Tage)
    public func withPaymentTerms(_ text: String, dueInDays days: Int? = nil) -> Invoice {
        var copy = self
        copy.paymentTerms = text
        if let days {
            copy.paymentDueDays = days
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
            copy.dueDate = calendar.date(byAdding: .day, value: days, to: issueDate) ?? issueDate
        }
        return copy
    }

    /// Fälligkeitsdatum direkt setzen
    public func withDueDate(_ date: Date) -> Invoice {
        var copy = self
        copy.dueDate = date
        return copy
    }

    /// Hinweise im Kopf der Rechnung (BT-22), ersetzt vorhandene
    public func withNotes(_ notes: [String]) -> Invoice {
        var copy = self
        copy.notes = notes
        return copy
    }

    /// Bestell-, Auftrags- und Vertragsnummer (BT-13, BT-14, BT-12)
    public func withReferences(buyerOrder: String? = nil, sellerOrder: String? = nil, contract: String? = nil) -> Invoice {
        var copy = self
        copy.buyerOrderNumber = buyerOrder
        copy.sellerOrderNumber = sellerOrder
        copy.contractNumber = contract
        return copy
    }

    /// Projektnummer und -name (BT-11)
    public func withProject(id: String?, name: String? = nil) -> Invoice {
        var copy = self
        copy.projectID = id
        copy.projectName = name
        return copy
    }

    public func withCurrency(_ code: String) -> Invoice {
        var copy = self
        copy.currency = code
        return copy
    }

    /// Macht die Rechnung zur Stornorechnung (Typ 381) zu einer früheren Rechnung (BT-25, BT-26)
    public func cancelling(number: String, issuedOn date: Date?) -> Invoice {
        var copy = self
        copy.cancelsNumber = number
        copy.cancelsDate = date
        return copy
    }

    // MARK: Prüfen und ausgeben

    /// Fehler und Hinweise zur Rechnung (`InvoiceCheck`)
    public func issues(today: Date = Date.now) -> [InvoiceIssue] {
        InvoiceCheck.issues(for: self, today: today)
    }

    /// Schreibt das E-Rechnungs-XML (CII). Ohne Profilangabe wird `preferredProfile` genommen: XRechnung für Rechnungen
    /// an Behörden (Käuferreferenz ist eine Leitweg-ID), sonst ZUGFeRD EN 16931.
    ///
    /// - Parameter validate: Prüft die Rechnung vorher mit `InvoiceCheck` und wirft bei Fehlern eine
    ///   `InvoiceValidationError` mit der Liste. Hinweise (Warnungen) verhindern das XML nicht.
    public func xml(profile: EInvoiceProfile? = nil, validate: Bool = true, attachments: [InvoiceAttachment] = []) throws -> String {
        if validate {
            let found = issues()
            if found.contains(where: { $0.severity == .error }) { throw InvoiceValidationError(issues: found) }
        }
        return try CIIWriter().xml(for: self, profile: profile ?? preferredProfile, attachments: attachments)
    }
}
