#if canImport(CoreGraphics) && canImport(CoreText)
import Foundation
import CoreGraphics
import CoreText

public enum RenderError: Error, LocalizedError {
    case contextFailed

    public var errorDescription: String? { "PDF-Kontext konnte nicht erzeugt werden" }
}

/// Zeichnet eine einfache A4-Rechnung mit Core Graphics / Core Text.
/// Die Schriften sind ausschließlich "Helvetica" und "Helvetica-Bold"; ob Core Graphics sie vollständig
/// einbettet (Pflicht für PDF/A), zeigt erst die Prüfung mit veraPDF.
public struct InvoicePDFRenderer {
    public init() {}

    private let pageWidth: CGFloat = 595.2756
    private let pageHeight: CGFloat = 841.8898
    private let left: CGFloat = 56
    private var right: CGFloat { pageWidth - 56 }

    public func render(_ invoice: Invoice) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw RenderError.contextFailed }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "Rechnung \(invoice.number)",
            kCGPDFContextAuthor: invoice.seller.name,
            kCGPDFContextCreator: "InvoiceKit Spike"
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw RenderError.contextFailed
        }

        ctx.beginPDFPage(nil)
        draw(invoice, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: - Layout

    private func draw(_ invoice: Invoice, in ctx: CGContext) {
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let gray = CGColor(srgbRed: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        ctx.setFillColor(black)
        ctx.setStrokeColor(black)
        ctx.setLineWidth(0.5)

        // Absender oben links
        text(ctx, invoice.seller.name, x: left, top: 60, size: 14, bold: true)
        text(ctx, invoice.seller.street, x: left, top: 76, size: 9, color: gray)
        text(ctx, "\(invoice.seller.postalCode) \(invoice.seller.city)", x: left, top: 88, size: 9, color: gray)
        text(ctx, invoice.seller.email, x: left, top: 100, size: 9, color: gray)

        // Empfänger
        text(ctx, invoice.buyer.name, x: left, top: 170, size: 11, bold: true)
        text(ctx, invoice.buyer.street, x: left, top: 185, size: 11)
        text(ctx, "\(invoice.buyer.postalCode) \(invoice.buyer.city)", x: left, top: 200, size: 11)

        // Titel und Eckdaten
        text(ctx, "Rechnung", x: left, top: 260, size: 20, bold: true)
        let metaLabelX: CGFloat = 330
        let meta: [(String, String)] = [
            ("Rechnungsnummer", invoice.number),
            ("Rechnungsdatum", DateFmt.german(invoice.issueDate)),
            ("Leistungszeitraum", "\(DateFmt.german(invoice.serviceStart)) – \(DateFmt.german(invoice.serviceEnd))"),
            ("Zahlbar bis", DateFmt.german(invoice.dueDate)),
            ("Ihre Referenz", invoice.buyerReference ?? "–")
        ]
        var metaTop: CGFloat = 244
        for (label, value) in meta {
            text(ctx, label, x: metaLabelX, top: metaTop, size: 9, color: gray)
            text(ctx, value, x: right, top: metaTop, size: 9, align: .right)
            metaTop += 13
        }

        // Positionstabelle
        let colPos: CGFloat = left
        let colName: CGFloat = left + 26
        let colQty: CGFloat = 330
        let colUnit: CGFloat = 338
        let colPrice: CGFloat = 430
        let colVat: CGFloat = 472
        let colTotal: CGFloat = right
        var top: CGFloat = 340
        text(ctx, "Pos.", x: colPos, top: top, size: 9, bold: true)
        text(ctx, "Beschreibung", x: colName, top: top, size: 9, bold: true)
        text(ctx, "Menge", x: colQty, top: top, size: 9, bold: true, align: .right)
        text(ctx, "Einzelpreis", x: colPrice, top: top, size: 9, bold: true, align: .right)
        text(ctx, "USt", x: colVat, top: top, size: 9, bold: true, align: .right)
        text(ctx, "Summe", x: colTotal, top: top, size: 9, bold: true, align: .right)
        line(ctx, from: left, to: right, top: top + 6)

        top += 22
        for (index, item) in invoice.items.enumerated() {
            text(ctx, String(index + 1), x: colPos, top: top, size: 10)
            text(ctx, item.name, x: colName, top: top, size: 10)
            text(ctx, Format.germanQuantity(item.quantity), x: colQty, top: top, size: 10, align: .right)
            text(ctx, item.unitLabel, x: colUnit, top: top, size: 10)
            text(ctx, Format.germanAmount(item.unitPrice), x: colPrice, top: top, size: 10, align: .right)
            text(ctx, "\(Format.germanPercent(item.vatRate)) %", x: colVat, top: top, size: 10, align: .right)
            text(ctx, Format.germanAmount(item.lineTotal), x: colTotal, top: top, size: 10, align: .right)
            top += 16
        }
        line(ctx, from: left, to: right, top: top - 6)

        // Summen
        top += 12
        let sumLabelX: CGFloat = 380
        text(ctx, "Nettosumme", x: sumLabelX, top: top, size: 10)
        text(ctx, Format.germanMoney(invoice.netTotal), x: right, top: top, size: 10, align: .right)
        top += 15
        for entry in invoice.vatBreakdown {
            text(ctx, "Umsatzsteuer \(Format.germanPercent(entry.rate)) %", x: sumLabelX, top: top, size: 10)
            text(ctx, Format.germanMoney(entry.tax), x: right, top: top, size: 10, align: .right)
            top += 15
        }
        line(ctx, from: sumLabelX, to: right, top: top - 8)
        text(ctx, "Gesamtbetrag", x: sumLabelX, top: top + 4, size: 11, bold: true)
        text(ctx, Format.germanMoney(invoice.grossTotal), x: right, top: top + 4, size: 11, bold: true, align: .right)

        // Zahlung und Hinweise
        top += 50
        text(ctx, invoice.paymentTerms, x: left, top: top, size: 10)
        top += 15
        var bank = "IBAN: \(invoice.iban)"
        if let bic = invoice.bic { bank += "   BIC: \(bic)" }
        text(ctx, bank, x: left, top: top, size: 10)
        top += 15
        text(ctx, "Verwendungszweck: \(invoice.number)", x: left, top: top, size: 10)
        if let note = invoice.note {
            top += 22
            text(ctx, note, x: left, top: top, size: 9, color: gray)
        }

        // Fußzeile
        line(ctx, from: left, to: right, top: 790)
        var footer = invoice.seller.name
        if let vat = invoice.seller.vatID { footer += "  ·  USt-IdNr.: \(vat)" }
        text(ctx, footer, x: left, top: 804, size: 8, color: gray)
    }

    // MARK: - Zeichenhilfen

    private enum Align { case left, right }

    private func text(
        _ ctx: CGContext,
        _ string: String,
        x: CGFloat,
        top: CGFloat,
        size: CGFloat,
        bold: Bool = false,
        color: CGColor? = nil,
        align: Align = .left
    ) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any
        ]
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary) else { return }
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let originX = align == .right ? x - width : x

        ctx.saveGState()
        ctx.setFillColor(color ?? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.textPosition = CGPoint(x: originX, y: pageHeight - top)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
    }

    private func line(_ ctx: CGContext, from x1: CGFloat, to x2: CGFloat, top: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x1, y: pageHeight - top))
        ctx.addLine(to: CGPoint(x: x2, y: pageHeight - top))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
#endif
