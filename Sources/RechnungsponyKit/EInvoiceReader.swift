import Foundation

public enum EInvoiceReaderError: Error, LocalizedError {
    case invalidXML(String)
    case notSupported(String)
    case missing(String)
    case noEmbeddedXML

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let m): return "Das XML ist nicht lesbar (\(m))."
        case .notSupported(let m): return "Nicht unterstützt: \(m)"
        case .missing(let f): return "In der E-Rechnung fehlt: \(f)"
        case .noEmbeddedXML: return "Das PDF enthält keine eingebettete E-Rechnung (kein ZUGFeRD/Factur-X)."
        }
    }
}

/// Ergebnis des Einlesens einer E-Rechnung.
public struct ParsedEInvoice {
    public var invoice: Invoice
    /// UNTDID 1001, z. B. "380" Rechnung, "381" Gutschrift
    public var typeCode: String
    public var guidelineID: String
    public var attachments: [InvoiceAttachment]
    /// Die Summen laut Datei; sie gelten für Auswertungen, auch wenn die Positionen anders rechnen
    public var declaredNet: Decimal?
    public var declaredTax: Decimal?
    public var declaredGross: Decimal?
    /// Auffälligkeiten beim Einlesen, die der Nutzer sehen sollte
    public var warnings: [String]
}

/// Eine eingelesene Datei samt Originalen, die unverändert archiviert werden.
public struct EInvoiceDocument {
    public var parsed: ParsedEInvoice
    public var xml: Data
    public var xmlFileName: String
    /// Das Original-PDF, wenn die Quelle ein PDF war
    public var pdf: Data?
}

/// Liest ZUGFeRD/Factur-X und XRechnung in CII-Syntax (UBL wird nicht gelesen).
public struct EInvoiceReader {
    public init() {}

    /// Liest ein PDF mit eingebettetem XML oder eine XML-Datei.
    public func read(_ data: Data, fileName: String = "") throws -> EInvoiceDocument {
        if data.prefix(5) == Data("%PDF-".utf8) {
            let files = PDFEmbeddedFiles.extract(from: data).filter { $0.name.lowercased().hasSuffix(".xml") }
            guard !files.isEmpty else { throw EInvoiceReaderError.noEmbeddedXML }
            let preferred = ["factur-x.xml", "zugferd-invoice.xml", "xrechnung.xml"]
            let ordered = files.sorted { a, b in
                (preferred.firstIndex(of: a.name.lowercased()) ?? 99) < (preferred.firstIndex(of: b.name.lowercased()) ?? 99)
            }
            var lastError: Error = EInvoiceReaderError.noEmbeddedXML
            for file in ordered {
                do {
                    let parsed = try parse(xml: file.data)
                    return EInvoiceDocument(parsed: parsed, xml: file.data, xmlFileName: file.name, pdf: data)
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
        let parsed = try parse(xml: data)
        let name = fileName.isEmpty ? "factur-x.xml" : fileName
        return EInvoiceDocument(parsed: parsed, xml: data, xmlFileName: name, pdf: nil)
    }

    public func parse(xml: Data) throws -> ParsedEInvoice {
        let root = try XMLTree.parse(xml)
        guard root.name == "CrossIndustryInvoice" else {
            if root.name == "Invoice" || root.name == "CreditNote" {
                throw EInvoiceReaderError.notSupported("XRechnung in UBL-Syntax (gelesen wird nur die CII-Syntax)")
            }
            throw EInvoiceReaderError.notSupported("Das ist keine E-Rechnung im CII-Format")
        }

        var warnings: [String] = []
        guard let number = root.string("ExchangedDocument/ID") else { throw EInvoiceReaderError.missing("die Rechnungsnummer") }
        let typeCode = root.string("ExchangedDocument/TypeCode") ?? "380"
        guard let issueDate = date(root.node("ExchangedDocument/IssueDateTime/DateTimeString")) else {
            throw EInvoiceReaderError.missing("das Rechnungsdatum")
        }
        let notes = (root.node("ExchangedDocument")?.all("IncludedNote") ?? []).compactMap { $0.string("Content") }
        let guideline = root.string("ExchangedDocumentContext/GuidelineSpecifiedDocumentContextParameter/ID") ?? ""

        guard let tx = root.child("SupplyChainTradeTransaction") else { throw EInvoiceReaderError.missing("die Rechnungsdaten") }
        guard let agreement = tx.child("ApplicableHeaderTradeAgreement") else { throw EInvoiceReaderError.missing("die Vertragsdaten") }
        let delivery = tx.child("ApplicableHeaderTradeDelivery")
        guard let settlement = tx.child("ApplicableHeaderTradeSettlement") else { throw EInvoiceReaderError.missing("die Zahlungsdaten") }

        // Positionen
        var items: [LineItem] = []
        for (index, line) in tx.all("IncludedSupplyChainTradeLineItem").enumerated() {
            let label = "Position \(index + 1)"
            var price = decimal(line.string("SpecifiedLineTradeAgreement/NetPriceProductTradePrice/ChargeAmount")) ?? 0
            if let basis = decimal(line.string("SpecifiedLineTradeAgreement/NetPriceProductTradePrice/BasisQuantity")), basis > 0, basis != 1 {
                price = price / basis
                warnings.append("\(label): Der Preis bezieht sich auf \(basis) Einheiten und wurde umgerechnet.")
            }
            let quantityNode = line.node("SpecifiedLineTradeDelivery/BilledQuantity")
            let quantity = decimal(quantityNode?.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let unit = quantityNode?.attributes["unitCode"] ?? "C62"
            let rate = decimal(line.string("SpecifiedLineTradeSettlement/ApplicableTradeTax/RateApplicablePercent")) ?? 0
            if let category = line.string("SpecifiedLineTradeSettlement/ApplicableTradeTax/CategoryCode"), category != "S" {
                warnings.append("\(label): Steuerkategorie \(category) statt S.")
            }
            if line.node("SpecifiedLineTradeSettlement/SpecifiedTradeAllowanceCharge") != nil {
                warnings.append("\(label): Zu- oder Abschläge auf Positionsebene werden nicht übernommen.")
            }
            let item = LineItem(
                name: line.string("SpecifiedTradeProduct/Name") ?? "",
                quantity: quantity,
                unitCode: unit,
                unitLabel: Self.unitLabel(unit),
                unitPrice: price,
                vatRate: rate,
                details: line.string("SpecifiedTradeProduct/Description")
            )
            if let declared = decimal(line.string("SpecifiedLineTradeSettlement/SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount")),
               declared != item.lineTotal {
                warnings.append("\(label): Der Positionsbetrag in der Datei (\(declared)) weicht von Menge × Preis (\(item.lineTotal)) ab.")
            }
            items.append(item)
        }

        // Zahlung
        let means = settlement.all("SpecifiedTradeSettlementPaymentMeans")
            .first { $0.string("PayeePartyCreditorFinancialAccount/IBANID") != nil }
        let iban = means?.string("PayeePartyCreditorFinancialAccount/IBANID") ?? ""
        let terms = settlement.all("SpecifiedTradePaymentTerms")
        var dueDate = issueDate
        if let due = terms.compactMap({ date($0.node("DueDateDateTime/DateTimeString")) }).first {
            dueDate = due
        } else {
            warnings.append("In der Datei steht kein Fälligkeitsdatum; es wurde das Rechnungsdatum gesetzt.")
        }
        let paymentTerms = terms.compactMap { $0.string("Description") }.first ?? ""

        // Zeitraum
        let deliveryDate = date(delivery?.node("ActualDeliverySupplyChainEvent/OccurrenceDateTime/DateTimeString"))
        let serviceStart = date(settlement.node("BillingSpecifiedPeriod/StartDateTime/DateTimeString")) ?? deliveryDate ?? issueDate
        let serviceEnd = date(settlement.node("BillingSpecifiedPeriod/EndDateTime/DateTimeString")) ?? deliveryDate ?? serviceStart

        // Anlagen (BG-24)
        var attachments: [InvoiceAttachment] = []
        for doc in agreement.all("AdditionalReferencedDocument") {
            guard let binary = doc.child("AttachmentBinaryObject"),
                  let data = Data(base64Encoded: binary.text, options: .ignoreUnknownCharacters), !data.isEmpty else { continue }
            let fileName = binary.attributes["filename"] ?? doc.string("Name") ?? "Anlage"
            let mime = binary.attributes["mimeCode"]
                ?? InvoiceAttachment.mimeType(forExtension: (fileName as NSString).pathExtension)
                ?? "application/octet-stream"
            attachments.append(InvoiceAttachment(fileName: fileName, mimeType: mime, data: data))
        }

        let calendar = Self.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: issueDate), to: calendar.startOfDay(for: dueDate)).day
        let sellerParty = party(agreement.child("SellerTradeParty"))
        let buyerParty = party(agreement.child("BuyerTradeParty"))
        let project = agreement.node("SpecifiedProcuringProject")

        let invoice = Invoice(
            number: number,
            issueDate: issueDate,
            serviceStart: serviceStart,
            serviceEnd: serviceEnd,
            dueDate: dueDate,
            seller: sellerParty,
            buyer: buyerParty,
            buyerReference: agreement.string("BuyerReference"),
            iban: iban,
            bic: means?.string("PayeeSpecifiedCreditorFinancialInstitution/BICID"),
            items: items,
            currency: settlement.string("InvoiceCurrencyCode") ?? "EUR",
            paymentTerms: paymentTerms,
            notes: notes,
            accountName: means?.string("PayeePartyCreditorFinancialAccount/AccountName"),
            buyerOrderNumber: agreement.string("BuyerOrderReferencedDocument/IssuerAssignedID"),
            sellerOrderNumber: agreement.string("SellerOrderReferencedDocument/IssuerAssignedID"),
            contractNumber: agreement.string("ContractReferencedDocument/IssuerAssignedID"),
            projectID: project?.string("ID"),
            projectName: project?.string("Name"),
            paymentDueDays: (days ?? 0) >= 0 ? days : nil
        )

        // Summen laut Datei
        let sum = settlement.node("SpecifiedTradeSettlementHeaderMonetarySummation")
        let declaredNet = decimal(sum?.string("TaxBasisTotalAmount")) ?? decimal(sum?.string("LineTotalAmount"))
        let declaredTax = decimal(sum?.string("TaxTotalAmount"))
        let declaredGross = decimal(sum?.string("GrandTotalAmount"))
        if settlement.node("SpecifiedTradeAllowanceCharge") != nil {
            warnings.append("Zu- oder Abschläge auf Rechnungsebene werden in den Positionen nicht abgebildet.")
        }
        if let declaredGross, declaredGross != invoice.grossTotal {
            warnings.append("Die Summe laut Datei (\(declaredGross)) weicht von der Summe der Positionen (\(invoice.grossTotal)) ab; die Summe laut Datei wird verwendet.")
        }

        return ParsedEInvoice(
            invoice: invoice,
            typeCode: typeCode,
            guidelineID: guideline,
            attachments: attachments,
            declaredNet: declaredNet,
            declaredTax: declaredTax,
            declaredGross: declaredGross,
            warnings: warnings
        )
    }

    // MARK: Hilfen

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DateFmt.berlin
        return c
    }()

    private static func unitLabel(_ code: String) -> String {
        switch code {
        case "HUR": return "Stunden"
        case "DAY": return "Tage"
        case "MON": return "Monate"
        case "H87", "C62": return "Stück"
        default: return code
        }
    }

    private func decimal(_ s: String?) -> Decimal? {
        guard let s, !s.isEmpty else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Format 102 (yyyyMMdd) oder ISO (yyyy-MM-dd)
    private func date(_ node: XMLElementNode?) -> Date? {
        guard let node else { return nil }
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits: String
        if text.contains("-") {
            digits = text.prefix(10).replacingOccurrences(of: "-", with: "")
        } else {
            digits = text
        }
        guard digits.count >= 8, let y = Int(digits.prefix(4)),
              let m = Int(digits.dropFirst(4).prefix(2)), let d = Int(digits.dropFirst(6).prefix(2)),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return DateFmt.make(y, m, d)
    }

    private func party(_ node: XMLElementNode?) -> Party {
        guard let node else { return Party(name: "", street: "", postalCode: "", city: "", email: "") }
        var vatID: String?
        var taxNumber: String?
        for registration in node.all("SpecifiedTaxRegistration") {
            guard let id = registration.string("ID") else { continue }
            switch registration.node("ID")?.attributes["schemeID"] {
            case "VA": vatID = vatID ?? id
            case "FC": taxNumber = taxNumber ?? id
            default: break
            }
        }
        let electronic = node.string("URIUniversalCommunication/URIID")
        let contactMail = node.string("DefinedTradeContact/EmailURIUniversalCommunication/URIID")
        let email = contactMail ?? (electronic?.contains("@") == true ? electronic : nil) ?? ""
        return Party(
            name: node.string("Name") ?? "",
            street: node.string("PostalTradeAddress/LineOne") ?? "",
            postalCode: node.string("PostalTradeAddress/PostcodeCode") ?? "",
            city: node.string("PostalTradeAddress/CityName") ?? "",
            countryCode: node.string("PostalTradeAddress/CountryID") ?? "DE",
            email: email,
            vatID: vatID,
            contactName: node.string("DefinedTradeContact/PersonName"),
            contactPhone: node.string("DefinedTradeContact/TelephoneUniversalCommunication/CompleteNumber"),
            electronicAddress: electronic,
            taxNumber: taxNumber,
            legalNote: node.string("Description")
        )
    }
}
