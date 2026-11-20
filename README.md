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

```swift
import RechnungsponyKit

let xml = try CIIWriter().xml(for: invoice, profile: .zugferdEN16931)

// PDF/A-3: eigenes PDF plus XML
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
