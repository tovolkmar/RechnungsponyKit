import Foundation

public enum EInvoiceProfile {
    /// ZUGFeRD 2.x / Factur-X, Profil EN 16931
    case zugferdEN16931
    /// XRechnung 3.0 in CII-Syntax
    case xrechnung

    /// BT-24 Spezifikationskennung
    public var guidelineID: String {
        switch self {
        case .zugferdEN16931: return "urn:cen.eu:en16931:2017"
        case .xrechnung: return "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"
        }
    }

    /// Dateiname der XML-Datei (als PDF-Anhang bzw. als Einzeldatei)
    public var fileName: String {
        switch self {
        case .zugferdEN16931: return "factur-x.xml"
        case .xrechnung: return "xrechnung.xml"
        }
    }

    /// Wert für fx:ConformanceLevel in den XMP-Metadaten
    public var conformanceLevel: String {
        switch self {
        case .zugferdEN16931: return "EN 16931"
        case .xrechnung: return "XRECHNUNG"
        }
    }
}

public enum InvoiceError: Error, LocalizedError {
    case missingField(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingField(let f): return "Pflichtfeld fehlt: \(f)"
        case .unsupported(let f): return "Noch nicht unterstützt: \(f)"
        }
    }
}

/// Erzeugt die Rechnung als UN/CEFACT Cross Industry Invoice (CII).
/// Die Reihenfolge der Elemente folgt dem CII-Schema (D16B); sie muss exakt stimmen.
public struct CIIWriter {
    public init() {}

    public func xml(for invoice: Invoice, profile: EInvoiceProfile, attachments: [InvoiceAttachment] = []) throws -> String {
        try validate(invoice, profile: profile)

        let x = XMLBuilder()
        x.raw("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        x.open("rsm:CrossIndustryInvoice", attrs: [
            "xmlns:rsm=\"urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100\"",
            "xmlns:qdt=\"urn:un:unece:uncefact:data:standard:QualifiedDataType:100\"",
            "xmlns:ram=\"urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100\"",
            "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"",
            "xmlns:udt=\"urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100\""
        ])

        // Kontext: Profil
        x.open("rsm:ExchangedDocumentContext")
        x.open("ram:GuidelineSpecifiedDocumentContextParameter")
        x.leaf("ram:ID", profile.guidelineID)
        x.close("ram:GuidelineSpecifiedDocumentContextParameter")
        x.close("rsm:ExchangedDocumentContext")

        // Kopf: Nummer, Typ (380 = Handelsrechnung), Datum
        x.open("rsm:ExchangedDocument")
        x.leaf("ram:ID", invoice.number)
        x.leaf("ram:TypeCode", invoice.isCancellation ? "381" : "380")
        x.open("ram:IssueDateTime")
        x.leaf("udt:DateTimeString", DateFmt.ymd(invoice.issueDate), attrs: ["format=\"102\""])
        x.close("ram:IssueDateTime")
        for note in invoice.notes where !note.isEmpty {
            x.open("ram:IncludedNote")
            x.leaf("ram:Content", note)
            x.close("ram:IncludedNote")
        }
        // Register- und Rechtsangaben des Verkäufers (§ 14 UStG) zusätzlich als Hinweis mit Betreffcode REG (BT-21),
        // wie es deutsche Rechnungsprogramme tun. Dieselbe Angabe steht als BT-33 am Verkäufer.
        if let legal = nonEmpty(invoice.seller.legalNote) {
            x.open("ram:IncludedNote")
            x.leaf("ram:Content", legal)
            x.leaf("ram:SubjectCode", "REG")
            x.close("ram:IncludedNote")
        }
        x.close("rsm:ExchangedDocument")

        x.open("rsm:SupplyChainTradeTransaction")

        // Positionen
        for (index, item) in invoice.items.enumerated() {
            x.open("ram:IncludedSupplyChainTradeLineItem")
            x.open("ram:AssociatedDocumentLineDocument")
            x.leaf("ram:LineID", String(index + 1))
            x.close("ram:AssociatedDocumentLineDocument")

            x.open("ram:SpecifiedTradeProduct")
            x.leaf("ram:Name", item.name)
            if let details = item.details, !details.isEmpty {
                x.leaf("ram:Description", details)
            }
            x.close("ram:SpecifiedTradeProduct")

            x.open("ram:SpecifiedLineTradeAgreement")
            x.open("ram:NetPriceProductTradePrice")
            x.leaf("ram:ChargeAmount", Format.xmlAmount(item.unitPrice))
            x.close("ram:NetPriceProductTradePrice")
            x.close("ram:SpecifiedLineTradeAgreement")

            x.open("ram:SpecifiedLineTradeDelivery")
            x.leaf("ram:BilledQuantity", Format.xmlQuantity(item.quantity), attrs: ["unitCode=\"\(XML.escape(item.unitCode))\""])
            x.close("ram:SpecifiedLineTradeDelivery")

            x.open("ram:SpecifiedLineTradeSettlement")
            x.open("ram:ApplicableTradeTax")
            x.leaf("ram:TypeCode", "VAT")
            x.leaf("ram:CategoryCode", item.taxCategory.rawValue)
            x.leaf("ram:RateApplicablePercent", Format.xmlPercent(item.effectiveVATRate))
            x.close("ram:ApplicableTradeTax")
            if let period = item.period {
                // BG-26: Leistungszeitraum der Position, steht nach der Steuer und vor der Positionssumme
                x.open("ram:BillingSpecifiedPeriod")
                x.open("ram:StartDateTime")
                x.leaf("udt:DateTimeString", DateFmt.ymd(period.start), attrs: ["format=\"102\""])
                x.close("ram:StartDateTime")
                x.open("ram:EndDateTime")
                x.leaf("udt:DateTimeString", DateFmt.ymd(period.end), attrs: ["format=\"102\""])
                x.close("ram:EndDateTime")
                x.close("ram:BillingSpecifiedPeriod")
            }
            x.open("ram:SpecifiedTradeSettlementLineMonetarySummation")
            x.leaf("ram:LineTotalAmount", Format.xmlAmount(item.lineTotal))
            x.close("ram:SpecifiedTradeSettlementLineMonetarySummation")
            x.close("ram:SpecifiedLineTradeSettlement")
            x.close("ram:IncludedSupplyChainTradeLineItem")
        }

        // Vereinbarung: Käuferreferenz, Verkäufer, Käufer
        x.open("ram:ApplicableHeaderTradeAgreement")
        if let reference = invoice.buyerReference, !reference.isEmpty {
            x.leaf("ram:BuyerReference", reference)
        }
        writeParty(x, tag: "ram:SellerTradeParty", party: invoice.seller, isSeller: true)
        writeParty(x, tag: "ram:BuyerTradeParty", party: invoice.buyer, isSeller: false)
        if let v = nonEmpty(invoice.sellerOrderNumber) {
            x.open("ram:SellerOrderReferencedDocument")
            x.leaf("ram:IssuerAssignedID", v)
            x.close("ram:SellerOrderReferencedDocument")
        }
        if let v = nonEmpty(invoice.buyerOrderNumber) {
            x.open("ram:BuyerOrderReferencedDocument")
            x.leaf("ram:IssuerAssignedID", v)
            x.close("ram:BuyerOrderReferencedDocument")
        }
        if let v = nonEmpty(invoice.contractNumber) {
            x.open("ram:ContractReferencedDocument")
            x.leaf("ram:IssuerAssignedID", v)
            x.close("ram:ContractReferencedDocument")
        }
        for (index, attachment) in attachments.enumerated() {
            x.open("ram:AdditionalReferencedDocument")
            x.leaf("ram:IssuerAssignedID", "Anlage-\(index + 1)")
            x.leaf("ram:TypeCode", "916")
            x.leaf("ram:Name", attachment.fileName)
            x.leaf("ram:AttachmentBinaryObject", attachment.data.base64EncodedString(),
                   attrs: ["mimeCode=\"\(XML.escape(attachment.mimeType))\"", "filename=\"\(XML.escape(attachment.fileName))\""])
            x.close("ram:AdditionalReferencedDocument")
        }
        if let id = nonEmpty(invoice.projectID) {
            x.open("ram:SpecifiedProcuringProject")
            x.leaf("ram:ID", id)
            x.leaf("ram:Name", nonEmpty(invoice.projectName) ?? id)
            x.close("ram:SpecifiedProcuringProject")
        }
        x.close("ram:ApplicableHeaderTradeAgreement")

        // Lieferung: Leistungsdatum (Ende des Leistungszeitraums)
        x.open("ram:ApplicableHeaderTradeDelivery")
        if let ship = invoice.shipTo?.orNil {
            // BG-13: Lieferinformation, steht in der CII-Reihenfolge vor dem Lieferereignis
            x.open("ram:ShipToTradeParty")
            if let name = nonEmpty(ship.name) { x.leaf("ram:Name", name) }
            x.open("ram:PostalTradeAddress")
            x.leaf("ram:PostcodeCode", ship.postalCode)
            x.leaf("ram:LineOne", ship.street)
            x.leaf("ram:CityName", ship.city)
            x.leaf("ram:CountryID", ship.countryCode)
            x.close("ram:PostalTradeAddress")
            x.close("ram:ShipToTradeParty")
        }
        x.open("ram:ActualDeliverySupplyChainEvent")
        x.open("ram:OccurrenceDateTime")
        x.leaf("udt:DateTimeString", DateFmt.ymd(invoice.serviceEnd), attrs: ["format=\"102\""])
        x.close("ram:OccurrenceDateTime")
        x.close("ram:ActualDeliverySupplyChainEvent")
        x.close("ram:ApplicableHeaderTradeDelivery")

        // Abrechnung
        x.open("ram:ApplicableHeaderTradeSettlement")
        if let debit = invoice.directDebit {
            x.leaf("ram:CreditorReferenceID", debit.creditorID)
        }
        x.leaf("ram:PaymentReference", invoice.number)
        x.leaf("ram:InvoiceCurrencyCode", invoice.currency)

        x.open("ram:SpecifiedTradeSettlementPaymentMeans")
        if let debit = invoice.directDebit {
            // BT-81 Zahlungsart 59 = SEPA-Lastschrift. Gezahlt wird vom Konto des Käufers (BG-19); ein Konto des
            // Zahlungsempfängers (BG-17) gehört nur zur Überweisung.
            x.leaf("ram:TypeCode", "59")
            x.leaf("ram:Information", "SEPA-Lastschrift")
            x.open("ram:PayerPartyDebtorFinancialAccount")
            x.leaf("ram:IBANID", IBANFormat.normalize(debit.debtorIBAN))
            x.close("ram:PayerPartyDebtorFinancialAccount")
        } else {
            // BT-81 Zahlungsart nach UNTDID 4461: 58 = SEPA-Überweisung (SEPA credit transfer), 30 = Überweisung allgemein
            // (credit transfer), 31 = Lastschrift-Überweisung (debit transfer, passt nicht zu einem Konto des Zahlungsempfängers
            // mit Zahlung durch den Käufer). Die Rechnung nennt ein IBAN-Konto im SEPA-Raum, daher 58; das ist die Empfehlung
            // von ZUGFeRD/Factur-X und von XRechnung. Mustang (ZUGFeRD 2.5, XRechnung 3.0) hat dazu keinen Hinweis.
            x.leaf("ram:TypeCode", "58")
            x.open("ram:PayeePartyCreditorFinancialAccount")
            x.leaf("ram:IBANID", invoice.iban.replacing(" ", with: ""))
            if let name = nonEmpty(invoice.accountName) { x.leaf("ram:AccountName", name) }
            x.close("ram:PayeePartyCreditorFinancialAccount")
            if let bic = invoice.bic, !bic.isEmpty {
                x.open("ram:PayeeSpecifiedCreditorFinancialInstitution")
                x.leaf("ram:BICID", bic)
                x.close("ram:PayeeSpecifiedCreditorFinancialInstitution")
            }
        }
        x.close("ram:SpecifiedTradeSettlementPaymentMeans")

        for line in invoice.vatBreakdown {
            x.open("ram:ApplicableTradeTax")
            x.leaf("ram:CalculatedAmount", Format.xmlAmount(line.tax))
            x.leaf("ram:TypeCode", "VAT")
            if let reason = line.exemptionReason { x.leaf("ram:ExemptionReason", reason) }
            x.leaf("ram:BasisAmount", Format.xmlAmount(line.basis))
            x.leaf("ram:CategoryCode", line.category.rawValue)
            x.leaf("ram:RateApplicablePercent", Format.xmlPercent(line.rate))
            x.close("ram:ApplicableTradeTax")
        }

        x.open("ram:BillingSpecifiedPeriod")
        x.open("ram:StartDateTime")
        x.leaf("udt:DateTimeString", DateFmt.ymd(invoice.serviceStart), attrs: ["format=\"102\""])
        x.close("ram:StartDateTime")
        x.open("ram:EndDateTime")
        x.leaf("udt:DateTimeString", DateFmt.ymd(invoice.serviceEnd), attrs: ["format=\"102\""])
        x.close("ram:EndDateTime")
        x.close("ram:BillingSpecifiedPeriod")

        x.open("ram:SpecifiedTradePaymentTerms")
        x.leaf("ram:Description", invoice.paymentTerms)
        x.open("ram:DueDateDateTime")
        x.leaf("udt:DateTimeString", DateFmt.ymd(invoice.dueDate), attrs: ["format=\"102\""])
        x.close("ram:DueDateDateTime")
        if let debit = invoice.directDebit {
            x.leaf("ram:DirectDebitMandateID", debit.mandateID)
        }
        x.close("ram:SpecifiedTradePaymentTerms")

        x.open("ram:SpecifiedTradeSettlementHeaderMonetarySummation")
        x.leaf("ram:LineTotalAmount", Format.xmlAmount(invoice.netTotal))
        x.leaf("ram:TaxBasisTotalAmount", Format.xmlAmount(invoice.netTotal))
        x.leaf("ram:TaxTotalAmount", Format.xmlAmount(invoice.taxTotal), attrs: ["currencyID=\"\(XML.escape(invoice.currency))\""])
        x.leaf("ram:GrandTotalAmount", Format.xmlAmount(invoice.grossTotal))
        x.leaf("ram:DuePayableAmount", Format.xmlAmount(invoice.grossTotal))
        x.close("ram:SpecifiedTradeSettlementHeaderMonetarySummation")

        if let cancelled = invoice.cancelsNumber {
            x.open("ram:InvoiceReferencedDocument")
            x.leaf("ram:IssuerAssignedID", cancelled)
            if let date = invoice.cancelsDate {
                x.open("ram:FormattedIssueDateTime")
                x.leaf("qdt:DateTimeString", DateFmt.ymd(date), attrs: ["format=\"102\""])
                x.close("ram:FormattedIssueDateTime")
            }
            x.close("ram:InvoiceReferencedDocument")
        }

        x.close("ram:ApplicableHeaderTradeSettlement")
        x.close("rsm:SupplyChainTradeTransaction")
        x.close("rsm:CrossIndustryInvoice")

        return x.output + "\n"
    }

    // MARK: - Teile

    private func writeParty(_ x: XMLBuilder, tag: String, party: Party, isSeller: Bool) {
        x.open(tag)
        x.leaf("ram:Name", party.name)
        if isSeller, let legal = nonEmpty(party.legalNote) {
            x.leaf("ram:Description", legal)
        }

        if isSeller, let contact = party.contactName {
            x.open("ram:DefinedTradeContact")
            x.leaf("ram:PersonName", contact)
            if let phone = party.contactPhone, !phone.isEmpty {
                x.open("ram:TelephoneUniversalCommunication")
                x.leaf("ram:CompleteNumber", phone)
                x.close("ram:TelephoneUniversalCommunication")
            }
            x.open("ram:EmailURIUniversalCommunication")
            x.leaf("ram:URIID", party.email)
            x.close("ram:EmailURIUniversalCommunication")
            x.close("ram:DefinedTradeContact")
        }

        x.open("ram:PostalTradeAddress")
        x.leaf("ram:PostcodeCode", party.postalCode)
        x.leaf("ram:LineOne", party.street)
        x.leaf("ram:CityName", party.city)
        x.leaf("ram:CountryID", party.countryCode)
        x.close("ram:PostalTradeAddress")

        // Elektronische Adresse (BT-34 / BT-49), Schema "EM" = E-Mail
        x.open("ram:URIUniversalCommunication")
        x.leaf("ram:URIID", nonEmpty(party.electronicAddress) ?? party.email, attrs: ["schemeID=\"EM\""])
        x.close("ram:URIUniversalCommunication")

        if let vatID = nonEmpty(party.vatID) {
            x.open("ram:SpecifiedTaxRegistration")
            x.leaf("ram:ID", vatID, attrs: ["schemeID=\"VA\""])
            x.close("ram:SpecifiedTaxRegistration")
        }
        if isSeller, let taxNumber = nonEmpty(party.taxNumber) {
            x.open("ram:SpecifiedTaxRegistration")
            x.leaf("ram:ID", taxNumber, attrs: ["schemeID=\"FC\""])
            x.close("ram:SpecifiedTaxRegistration")
        }
        x.close(tag)
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    private func validate(_ invoice: Invoice, profile: EInvoiceProfile) throws {
        if invoice.items.isEmpty { throw InvoiceError.missingField("Rechnungspositionen") }
        if nonEmpty(invoice.seller.vatID) == nil && nonEmpty(invoice.seller.taxNumber) == nil { throw InvoiceError.unsupported("Verkäufer ohne USt-IdNr. (Steuernummer, Kleinunternehmer)") }
        if let debit = invoice.directDebit {
            // Lastschrift braucht das Konto des Käufers (BT-91), die Mandatsreferenz (BT-89) und die Gläubiger-ID (BT-90)
            if nonEmpty(debit.debtorIBAN) == nil { throw InvoiceError.missingField("IBAN des Käufers für die Lastschrift (BT-91)") }
            if nonEmpty(debit.mandateID) == nil { throw InvoiceError.missingField("Mandatsreferenz (BT-89)") }
            if nonEmpty(debit.creditorID) == nil { throw InvoiceError.missingField("Gläubiger-Identifikationsnummer (BT-90)") }
        }
        for item in invoice.items {
            // BR-S-05: Kategorie S verlangt einen Satz über 0 %; Nullsatz und Steuerfreiheit haben ihre eigene Kategorie
            if item.taxCategory == .standard, item.vatRate <= 0 {
                throw InvoiceError.unsupported("Steuersatz 0 % in „\(item.name)“ (dafür die Kategorie „Steuerfrei“ oder „0 %“ wählen)")
            }
            // BR-E-10: Steuerfreie Positionen brauchen einen Befreiungsgrund
            if item.taxCategory.needsExemptionReason, item.trimmedExemptionReason == nil {
                throw InvoiceError.missingField("Befreiungsgrund (BT-120) für „\(item.name)“")
            }
        }
        if profile == .xrechnung {
            // Zusätzliche Geschäftsregeln der XRechnung (BR-DE-*)
            if (invoice.buyerReference ?? "").isEmpty { throw InvoiceError.missingField("Käuferreferenz / Leitweg-ID (BT-10)") }
            if (invoice.seller.contactName ?? "").isEmpty { throw InvoiceError.missingField("Ansprechpartner des Verkäufers (BG-6)") }
            if (invoice.seller.contactPhone ?? "").isEmpty { throw InvoiceError.missingField("Telefon des Verkäufers (BT-42)") }
        }
    }
}

// MARK: - Mini-XML-Builder

final class XMLBuilder {
    private var lines: [String] = []
    private var depth = 0

    private var indent: String { String(repeating: "  ", count: depth) }

    func raw(_ line: String) {
        lines.append(line)
    }

    func open(_ tag: String, attrs: [String] = []) {
        let a = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")
        lines.append("\(indent)<\(tag)\(a)>")
        depth += 1
    }

    func close(_ tag: String) {
        depth -= 1
        lines.append("\(indent)</\(tag)>")
    }

    func leaf(_ tag: String, _ text: String, attrs: [String] = []) {
        let a = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")
        lines.append("\(indent)<\(tag)\(a)>\(XML.escape(text))</\(tag)>")
    }

    var output: String { lines.joined(separator: "\n") }
}
