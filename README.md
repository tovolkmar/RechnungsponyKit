# RechnungsponyKit

Swift-Paket zum Erzeugen und Lesen von **E-Rechnungen** nach EN 16931: **ZUGFeRD** (PDF/A-3 mit eingebettetem XML) und **XRechnung** (CII-Syntax). Es stammt aus der Rechnungs-App *Rechnungspony*.

*Swift package for creating and reading EN 16931 e-invoices (ZUGFeRD / Factur-X PDF/A-3 and XRechnung in CII syntax). Apple platforms only (macOS 14, iOS 17).*

> **Status: 0.9.** Die API kann sich bis 1.0 noch ändern. Die Ausgabe ersetzt keine Prüfung: Validiere erzeugte Rechnungen mit [Mustang](https://www.mustangproject.org/) oder dem KoSIT-Validator, bevor du sie produktiv versendest. Keine Rechts- oder Steuerberatung, keine Gewähr.

## Was drin ist

- `Invoice`: Rechnungsmodell (Beträge als `Decimal`, kaufmännisch gerundet), Steuerkategorien S, Z und E, abweichende Lieferanschrift (BG-13), SEPA-Lastschrift (BG-19), Leistungszeitraum je Position (BG-26)
- `CIIWriter`: schreibt das CII-XML als Profil EN 16931 (`.zugferdEN16931`) oder `.xrechnung` (inkl. BT-23)
- `EInvoiceReader`: liest ZUGFeRD-PDFs und XML-Dateien ein
- `PDFA3Packer`: bettet das XML in ein PDF ein und erzeugt PDF/A-3u-Metadaten (XMP)
- `InvoicePDFRenderer`: einfaches A4-Rechnungs-PDF zum Ausprobieren; für echte Rechnungen nimmst du dein eigenes Layout
- `InvoiceCheck`: Prüfung vor dem Ausstellen (Pflichtangaben, IBAN, USt-IdNr., Leitweg-ID)

Nicht unterstützt: Reverse Charge, innergemeinschaftliche Lieferung und Drittland (Steuerkategorien AE, K, G, O).

## Einbinden

```swift
.package(url: "https://github.com/tovolkmar/RechnungsponyKit.git", from: "0.9.0")
```

## Beispiel

### XML aus einzelnen Angaben erzeugen

`Invoice` ist ein Werttyp. Jede `with…`-Methode liefert eine geänderte Kopie zurück, so setzt du Absender, Empfänger, Positionen und Zahlungsangaben nacheinander und bekommst am Ende das XML:

```swift
import RechnungsponyKit

let seller = Party(name: "Muster GmbH", street: "Beispielweg 1", postalCode: "80331", city: "München",
                   email: "rechnung@muster.example", vatID: "DE123456789")
let buyer = Party(name: "Kunde AG", street: "Hauptstraße 2", postalCode: "10115", city: "Berlin",
                  email: "buchhaltung@kunde.example")

let xml = try Invoice(number: "RE-2026-0001", issueDate: .now)
    .withSeller(seller)
    .withBuyer(buyer)
    .withServicePeriod(from: start, to: end)
    .addingLine(name: "Beratung", quantity: 8, unit: .hour, unitPrice: 95, vatRate: 19)
    .addingLine(name: "Reisekosten", quantity: 1, unit: .lumpSum, unitPrice: 80)
    .withBankAccount(iban: "DE02 1203 0000 0000 2020 51", bic: "BYLADEM1001")
    .withPaymentTerms("Zahlbar innerhalb von 14 Tagen", dueInDays: 14)
    .xml()   // Profil automatisch: XRechnung bei Leitweg-ID als Käuferreferenz, sonst ZUGFeRD EN 16931
```

`xml()` prüft die Rechnung vorher (`InvoiceCheck`) und wirft bei Fehlern eine `InvoiceValidationError`, deren `errors` sagen, was fehlt (zum Beispiel Anschrift, E-Mail, IBAN). Hinweise (Warnungen) liefert `invoice.issues()`. Mit `xml(validate: false)` überspringst du die Prüfung, mit `xml(profile: .xrechnung)` wählst du das Profil selbst.

Weitere Setter: `withShipTo`, `withBuyerReference`, `withDirectDebit`, `withReferences(buyerOrder:sellerOrder:contract:)`, `withProject`, `withNotes`, `withCurrency`, `withDueDate`, `withLines`, `cancelling(number:issuedOn:)` für Stornorechnungen. Steuerfreie Positionen: `addingLine(…, vatRate: 0, taxCategory: .exempt, exemptionReason: "…")`. Summen, Steuerzusammenfassung und Rundung berechnet das Paket selbst.

### ZUGFeRD-PDF und Lesen

```swift
// PDF/A-3: eigenes PDF plus XML (als ICC-Profil nimmt das Paket sRGB vom System, abweichend per `iccProfile:`)
let options = PDFA3Packer.Options(title: "Rechnung", author: "Muster GmbH")
let pdfA3 = try PDFA3Packer().pack(pdf: pdfData, xml: Data(xml.utf8), options: options)

// Lesen
let document = try EInvoiceReader().read(fileData, fileName: "rechnung.pdf")
print(document.parsed.invoice.number)
```

## Entwicklung

```bash
swift test
```

## Lizenz

MIT, siehe [LICENSE](LICENSE).
