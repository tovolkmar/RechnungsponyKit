import Foundation

/// Rechnungssteller oder -empfänger.
public struct Party: Codable, Equatable, Sendable {
    public var name: String
    public var street: String
    public var postalCode: String
    public var city: String
    public var countryCode: String
    public var email: String
    public var vatID: String?
    public var contactName: String?
    public var contactPhone: String?
    /// Elektronische Adresse (BT-34 / BT-49); Standard ist die E-Mail-Adresse
    public var electronicAddress: String?
    /// Steuernummer (Schema "FC"), zusätzlich oder statt der USt-IdNr.
    public var taxNumber: String?
    /// Freitext zum Verkäufer (BT-33), z. B. Register- und Geschäftsführerangaben
    public var legalNote: String?

    public init(
        name: String,
        street: String,
        postalCode: String,
        city: String,
        countryCode: String = "DE",
        email: String,
        vatID: String? = nil,
        contactName: String? = nil,
        contactPhone: String? = nil,
        electronicAddress: String? = nil,
        taxNumber: String? = nil,
        legalNote: String? = nil
    ) {
        self.name = name
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.countryCode = countryCode
        self.email = email
        self.vatID = vatID
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.electronicAddress = electronicAddress
        self.taxNumber = taxNumber
        self.legalNote = legalNote
    }
}

public struct LineItem: Codable, Equatable, Sendable {
    public var name: String
    public var quantity: Decimal
    /// UN/ECE Recommendation 20, z. B. "HUR" (Stunde), "DAY" (Tag), "C62" (Stück)
    public var unitCode: String
    /// Anzeige im PDF, z. B. "Std."
    public var unitLabel: String
    /// Nettopreis je Einheit
    public var unitPrice: Decimal
    /// Umsatzsteuersatz in Prozent, z. B. 19
    public var vatRate: Decimal
    /// Beschreibung der Position (BT-154), kann Zeilenumbrüche enthalten
    public var details: String?

    public init(name: String, quantity: Decimal, unitCode: String, unitLabel: String, unitPrice: Decimal, vatRate: Decimal, details: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.unitCode = unitCode
        self.unitLabel = unitLabel
        self.unitPrice = unitPrice
        self.vatRate = vatRate
        self.details = details
    }

    public var lineTotal: Decimal { (quantity * unitPrice).rounded2() }
}

public struct VATBreakdown: Sendable {
    public let rate: Decimal
    public let basis: Decimal
    public let tax: Decimal
}

public struct Invoice: Codable, Equatable, Sendable {
    public var number: String
    public var issueDate: Date
    public var serviceStart: Date
    public var serviceEnd: Date
    public var dueDate: Date
    public var seller: Party
    public var buyer: Party
    /// Leitweg-ID bei Rechnungen an Behörden (BT-10), sonst eine beliebige Referenz des Käufers
    public var buyerReference: String?
    public var iban: String
    public var bic: String?
    public var items: [LineItem]
    public var currency: String
    public var paymentTerms: String
    /// Hinweise im Kopf der Rechnung (BT-22); der erste erscheint auch im PDF
    public var notes: [String]
    public var accountName: String?
    /// Bestellnummer des Käufers (BT-13)
    public var buyerOrderNumber: String?
    /// Auftragsnummer des Verkäufers (BT-14)
    public var sellerOrderNumber: String?
    /// Rahmenvertragsnummer (BT-12)
    public var contractNumber: String?
    /// Projektnummer und -name (BT-11)
    public var projectID: String?
    public var projectName: String?
    /// Zahlungsziel in Tagen, nur für die Anzeige im PDF
    public var paymentDueDays: Int?
    /// Nummer der stornierten Rechnung (BT-25); gesetzt ⇒ Stornorechnung (Typ 381)
    public var cancelsNumber: String?
    /// Rechnungsdatum der stornierten Rechnung (BT-26)
    public var cancelsDate: Date?

    /// Stornorechnung (Gutschrift zu einer eigenen Rechnung, positive Beträge)
    public var isCancellation: Bool { cancelsNumber != nil }

    public var note: String? { notes.first }

    public init(
        number: String,
        issueDate: Date,
        serviceStart: Date,
        serviceEnd: Date,
        dueDate: Date,
        seller: Party,
        buyer: Party,
        buyerReference: String? = nil,
        iban: String,
        bic: String? = nil,
        items: [LineItem],
        currency: String = "EUR",
        paymentTerms: String,
        note: String? = nil,
        notes: [String] = [],
        accountName: String? = nil,
        buyerOrderNumber: String? = nil,
        sellerOrderNumber: String? = nil,
        contractNumber: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        paymentDueDays: Int? = nil,
        cancelsNumber: String? = nil,
        cancelsDate: Date? = nil
    ) {
        self.number = number
        self.issueDate = issueDate
        self.serviceStart = serviceStart
        self.serviceEnd = serviceEnd
        self.dueDate = dueDate
        self.seller = seller
        self.buyer = buyer
        self.buyerReference = buyerReference
        self.iban = iban
        self.bic = bic
        self.items = items
        self.currency = currency
        self.paymentTerms = paymentTerms
        self.notes = notes.isEmpty ? (note.map { [$0] } ?? []) : notes
        self.accountName = accountName
        self.buyerOrderNumber = buyerOrderNumber
        self.sellerOrderNumber = sellerOrderNumber
        self.contractNumber = contractNumber
        self.projectID = projectID
        self.projectName = projectName
        self.paymentDueDays = paymentDueDays
        self.cancelsNumber = cancelsNumber
        self.cancelsDate = cancelsDate
    }

    public var netTotal: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.lineTotal }
    }

    public var vatBreakdown: [VATBreakdown] {
        let rates = Set(items.map { $0.vatRate }).sorted()
        return rates.map { rate in
            let basis = items.filter { $0.vatRate == rate }.reduce(Decimal(0)) { $0 + $1.lineTotal }
            let tax = (basis * rate / 100).rounded2()
            return VATBreakdown(rate: rate, basis: basis, tax: tax)
        }
    }

    public var taxTotal: Decimal {
        vatBreakdown.reduce(Decimal(0)) { $0 + $1.tax }
    }

    public var grossTotal: Decimal { netTotal + taxTotal }
}

/// Feste Testrechnung mit erfundenen Daten für den Spike.
public enum SampleInvoice {
    public static func make() -> Invoice {
        let seller = Party(
            name: "Mustermann Softwareentwicklung",
            street: "Beispielweg 1",
            postalCode: "80331",
            city: "München",
            email: "rechnung@mustermann-software.example",
            vatID: "DE123456789",
            contactName: "Max Mustermann",
            contactPhone: "+49 89 1234567"
        )
        let buyer = Party(
            name: "Beispiel AG",
            street: "Musterstraße 12",
            postalCode: "10115",
            city: "Berlin",
            email: "eingang@beispiel-ag.example"
        )
        let items = [
            LineItem(name: "Softwareentwicklung September 2026", quantity: dec("16"), unitCode: "HUR", unitLabel: "Std.", unitPrice: dec("95.00"), vatRate: dec("19")),
            LineItem(name: "Pauschale Reisekosten", quantity: dec("1"), unitCode: "C62", unitLabel: "Stk.", unitPrice: dec("80.00"), vatRate: dec("19"))
        ]
        return Invoice(
            number: "RE-2026-0001",
            issueDate: DateFmt.make(2026, 10, 8),
            serviceStart: DateFmt.make(2026, 9, 1),
            serviceEnd: DateFmt.make(2026, 9, 30),
            dueDate: DateFmt.make(2026, 10, 22),
            seller: seller,
            buyer: buyer,
            buyerReference: "04011000-1234512345-35",
            iban: "DE02120300000000202051",
            bic: "BYLADEM1001",
            items: items,
            paymentTerms: "Zahlbar innerhalb von 14 Tagen ohne Abzug",
            note: "Testrechnung mit erfundenen Daten."
        )
    }
}

/// Anlage zur Rechnung, z. B. ein Zeitnachweis (BG-24). Wird im PDF/A-3 und im XML eingebettet.
public struct InvoiceAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var fileName: String
    public var mimeType: String
    public var data: Data

    public init(id: UUID = UUID(), fileName: String, mimeType: String, data: Data) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }

    /// Erlaubte Formate nach EN 16931 (BR-CL-24), soweit die App sie anbietet
    public static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "csv": return "text/csv"
        default: return nil
        }
    }
}
