import Foundation

public enum PackError: Error, LocalizedError {
    case malformed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let m): return "PDF nicht lesbar: \(m)"
        case .unsupported(let m): return "PDF-Aufbau nicht unterstützt: \(m)"
        }
    }
}

/// Macht aus einem fertigen PDF ein ZUGFeRD-/Factur-X-PDF (PDF/A-3b mit eingebettetem XML).
///
/// Vorgehen: Das Original-PDF bleibt unverändert, am Ende wird ein "inkrementelles Update" angehängt
/// (neue Objekte, neue Querverweistabelle, ersetzter Katalog). Das Original muss eine klassische
/// Querverweistabelle haben (kein Xref-Stream, keine Object-Streams), wie sie Core Graphics erzeugt.
///
/// Wichtig: Das Ergebnis ist nur dann PDF/A-3b-konform, wenn auch das Original-PDF es zulässt
/// (alle Schriften eingebettet, keine verbotenen Elemente). Das prüft veraPDF, nicht dieser Code.
public struct PDFA3Packer {
    public init() {}

    public struct Options {
        public var title: String
        public var author: String
        public var producer: String
        public var creatorTool: String
        public var date: Date
        public var xmlFileName: String
        public var conformanceLevel: String
        public var attachmentDescription: String
        /// ICC-Profil für DeviceRGB (sRGB), wird als OutputIntent eingebettet
        public var iccProfile: Data
        public var iccName: String

        public init(
            title: String,
            author: String,
            producer: String = "InvoiceKit Spike",
            creatorTool: String = "InvoiceKit Spike",
            date: Date = Date.now,
            xmlFileName: String = "factur-x.xml",
            conformanceLevel: String = "EN 16931",
            attachmentDescription: String = "Factur-X Invoice",
            iccProfile: Data,
            iccName: String = "sRGB IEC61966-2.1"
        ) {
            self.title = title
            self.author = author
            self.producer = producer
            self.creatorTool = creatorTool
            self.date = date
            self.xmlFileName = xmlFileName
            self.conformanceLevel = conformanceLevel
            self.attachmentDescription = attachmentDescription
            self.iccProfile = iccProfile
            self.iccName = iccName
        }
    }

    public func pack(pdf: Data, xml: Data, options: Options, attachments: [InvoiceAttachment] = []) throws -> Data {
        let bytes = [UInt8](pdf)

        // 1. Letzte startxref-Angabe finden
        guard let sxPos = lastIndex(of: "startxref", in: bytes) else {
            throw PackError.malformed("startxref fehlt")
        }
        guard let xrefOffset = readInt(in: bytes, from: sxPos + "startxref".utf8.count) else {
            throw PackError.malformed("startxref ohne Zahl")
        }
        guard xrefOffset >= 0, xrefOffset < bytes.count,
              startsWith("xref", in: bytes, at: xrefOffset) else {
            throw PackError.unsupported("Querverweis-Stream statt klassischer xref-Tabelle")
        }

        // 2. Querverweistabelle und Trailer lesen
        let region = String(decoding: bytes[xrefOffset...], as: UTF8.self)
        let lines = region.split(whereSeparator: { $0.isNewline }).map { String($0) }
        var offsets: [Int: Int] = [:]
        var index = 1
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("trailer") { break }
            let parts = line.split(separator: " ")
            guard parts.count == 2, let first = Int(parts[0]), let count = Int(parts[1]) else {
                throw PackError.malformed("xref-Abschnitt: \(line)")
            }
            index += 1
            for k in 0..<count {
                guard index < lines.count else { throw PackError.malformed("xref zu kurz") }
                let entry = lines[index].split(separator: " ")
                guard entry.count >= 3, let off = Int(entry[0]) else {
                    throw PackError.malformed("xref-Eintrag: \(lines[index])")
                }
                if entry[2] == "n" { offsets[first + k] = off }
                index += 1
            }
        }
        guard index < lines.count else { throw PackError.malformed("trailer fehlt") }
        let trailerText = lines[index...].joined(separator: "\n")

        guard trailerText.range(of: "/Prev") == nil else {
            throw PackError.unsupported("Trailer mit /Prev (PDF wurde schon inkrementell geändert)")
        }
        guard let size = firstInt(in: trailerText, pattern: "/Size\\s+(\\d+)") else {
            throw PackError.malformed("/Size fehlt")
        }
        guard let rootMatch = captures(in: trailerText, pattern: "/Root\\s+(\\d+)\\s+(\\d+)\\s+R"),
              rootMatch.count == 2, let rootID = Int(rootMatch[0]), let rootGen = Int(rootMatch[1]) else {
            throw PackError.malformed("/Root fehlt")
        }
        guard rootGen == 0 else { throw PackError.unsupported("Katalog mit Generation \(rootGen)") }
        guard let rootOffset = offsets[rootID] else { throw PackError.malformed("Katalog nicht in xref") }

        // 3. Katalog-Dictionary lesen
        guard let endObj = indexOf("endobj", in: bytes, from: rootOffset) else {
            throw PackError.malformed("Katalog ohne endobj")
        }
        let catalogBytes = Array(bytes[rootOffset..<endObj])
        guard let (dictStart, dictEnd) = topLevelDictionary(in: catalogBytes) else {
            throw PackError.malformed("Katalog ist kein Dictionary")
        }
        let inner = String(decoding: catalogBytes[(dictStart + 2)..<dictEnd], as: UTF8.self)
        for key in ["/Metadata", "/OutputIntents", "/AF", "/Names"] where inner.contains(key) {
            throw PackError.unsupported("Katalog enthält schon \(key)")
        }

        // 4. Neue Objekte
        let iccID = size
        let intentID = size + 1
        let xmpID = size + 2
        let fileID = size + 3
        let specID = size + 4
        let infoID = size + 5
        let attachmentBase = size + 6
        let newSize = size + 6 + 2 * attachments.count

        var out = pdf
        if let last = out.last, last != 0x0A { out.appendString("\n") }
        var newOffsets: [Int: Int] = [:]

        let pdfDate = "D:" + DateFmt.format(options.date, "yyyyMMddHHmmss", timeZone: DateFmt.utc) + "+00'00'"
        let xmp = XMPBuilder.packet(
            title: options.title,
            author: options.author,
            producer: options.producer,
            creatorTool: options.creatorTool,
            date: options.date,
            attachmentFileName: options.xmlFileName,
            conformanceLevel: options.conformanceLevel
        )

        newOffsets[iccID] = out.count
        out.append(streamObject(id: iccID, dict: "/N 3", data: options.iccProfile))

        newOffsets[intentID] = out.count
        out.appendString("\(intentID) 0 obj\n<< /Type /OutputIntent /S /GTS_PDFA1 /OutputConditionIdentifier \(pdfString(options.iccName)) /RegistryName (http://www.color.org) /Info \(pdfString(options.iccName)) /DestOutputProfile \(iccID) 0 R >>\nendobj\n")

        newOffsets[xmpID] = out.count
        out.append(streamObject(id: xmpID, dict: "/Type /Metadata /Subtype /XML", data: xmp))

        newOffsets[fileID] = out.count
        out.append(streamObject(
            id: fileID,
            dict: "/Type /EmbeddedFile /Subtype /text#2Fxml /Params << /Size \(xml.count) /ModDate (\(pdfDate)) >>",
            data: xml
        ))

        let name = pdfString(options.xmlFileName)
        newOffsets[specID] = out.count
        out.appendString("\(specID) 0 obj\n<< /Type /Filespec /F \(name) /UF \(name) /Desc \(pdfString(options.attachmentDescription)) /AFRelationship /Alternative /EF << /F \(fileID) 0 R /UF \(fileID) 0 R >> >>\nendobj\n")

        // Weitere Anlagen (z. B. Zeitnachweis), Beziehung "Supplement"
        var specRefs: [(name: String, id: Int)] = [(name, specID)]
        var usedNames: Set<String> = [options.xmlFileName]
        for (index, attachment) in attachments.enumerated() {
            let embeddedID = attachmentBase + 2 * index
            let attachmentSpecID = embeddedID + 1
            var fileName = attachment.fileName
            if usedNames.contains(fileName) {
                let ext = (fileName as NSString).pathExtension
                let base = (fileName as NSString).deletingPathExtension
                fileName = "\(base)-\(index + 1)" + (ext.isEmpty ? "" : ".\(ext)")
            }
            usedNames.insert(fileName)
            let subtype = attachment.mimeType.replacing("/", with: "#2F")
            newOffsets[embeddedID] = out.count
            out.append(streamObject(
                id: embeddedID,
                dict: "/Type /EmbeddedFile /Subtype /\(subtype) /Params << /Size \(attachment.data.count) /ModDate (\(pdfDate)) >>",
                data: attachment.data
            ))
            let n = pdfString(fileName)
            newOffsets[attachmentSpecID] = out.count
            out.appendString("\(attachmentSpecID) 0 obj\n<< /Type /Filespec /F \(n) /UF \(n) /Desc \(pdfString(fileName)) /AFRelationship /Supplement /EF << /F \(embeddedID) 0 R /UF \(embeddedID) 0 R >> >>\nendobj\n")
            specRefs.append((n, attachmentSpecID))
        }
        // Namensbaum muss nach Namen sortiert sein
        specRefs.sort { $0.name < $1.name }
        let afArray = specRefs.map { "\($0.id) 0 R" }.joined(separator: " ")
        let namesArray = specRefs.map { "\($0.name) \($0.id) 0 R" }.joined(separator: " ")

        newOffsets[infoID] = out.count
        out.appendString("\(infoID) 0 obj\n<< /Title \(pdfString(options.title)) /Author \(pdfString(options.author)) /Producer \(pdfString(options.producer)) /Creator \(pdfString(options.creatorTool)) /CreationDate (\(pdfDate)) /ModDate (\(pdfDate)) >>\nendobj\n")

        // Katalog ersetzen (gleiche Objektnummer, neuer Inhalt)
        newOffsets[rootID] = out.count
        out.appendString("\(rootID) 0 obj\n<<\(inner) /Metadata \(xmpID) 0 R /OutputIntents [\(intentID) 0 R] /AF [\(afArray)] /Names << /EmbeddedFiles << /Names [\(namesArray)] >> >> >>\nendobj\n")

        // 5. Neue Querverweistabelle (nur geänderte Objekte), Trailer
        let newXrefOffset = out.count
        out.appendString("xref\n")
        let ids = newOffsets.keys.sorted()
        var i = 0
        while i < ids.count {
            var j = i
            while j + 1 < ids.count && ids[j + 1] == ids[j] + 1 { j += 1 }
            out.appendString("\(ids[i]) \(j - i + 1)\n")
            for k in i...j {
                out.appendString("\(pad10(newOffsets[ids[k]] ?? 0)) 00000 n \n")
            }
            i = j + 1
        }

        let originalID = captures(in: trailerText, pattern: "/ID\\s*\\[\\s*<([0-9A-Fa-f]+)>\\s*<([0-9A-Fa-f]+)>\\s*\\]")
        let firstID = originalID?.first ?? randomHex(16)
        let secondID = randomHex(16)
        out.appendString("trailer\n<< /Size \(newSize) /Root \(rootID) 0 R /Info \(infoID) 0 R /Prev \(xrefOffset) /ID [<\(firstID)> <\(secondID)>] >>\nstartxref\n\(newXrefOffset)\n%%EOF\n")
        return out
    }

    // MARK: - PDF-Bausteine

    private func streamObject(id: Int, dict: String, data: Data) -> Data {
        var d = Data()
        d.appendString("\(id) 0 obj\n<< \(dict) /Length \(data.count) >>\nstream\n")
        d.append(data)
        d.appendString("\nendstream\nendobj\n")
        return d
    }

    /// PDF-Textstring: ASCII in Klammern, sonst UTF-16BE als Hex.
    func pdfString(_ s: String) -> String {
        let isPlain = s.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
        if isPlain {
            let escaped = s
                .replacing("\\", with: "\\\\")
                .replacing("(", with: "\\(")
                .replacing(")", with: "\\)")
            return "(\(escaped))"
        }
        var hex = "FEFF"
        for unit in s.utf16 {
            let h = String(unit, radix: 16, uppercase: true)
            hex += String(repeating: "0", count: 4 - h.count) + h
        }
        return "<\(hex)>"
    }

    // MARK: - Byte-Suche

    private func lastIndex(of pattern: String, in bytes: [UInt8]) -> Int? {
        let p = Array(pattern.utf8)
        guard bytes.count >= p.count else { return nil }
        var i = bytes.count - p.count
        while i >= 0 {
            if bytes[i] == p[0] && Array(bytes[i..<(i + p.count)]) == p { return i }
            i -= 1
        }
        return nil
    }

    private func indexOf(_ pattern: String, in bytes: [UInt8], from start: Int) -> Int? {
        let p = Array(pattern.utf8)
        guard bytes.count >= p.count, start <= bytes.count - p.count else { return nil }
        var i = start
        while i <= bytes.count - p.count {
            if bytes[i] == p[0] && Array(bytes[i..<(i + p.count)]) == p { return i }
            i += 1
        }
        return nil
    }

    private func startsWith(_ pattern: String, in bytes: [UInt8], at offset: Int) -> Bool {
        let p = Array(pattern.utf8)
        guard offset + p.count <= bytes.count else { return false }
        return Array(bytes[offset..<(offset + p.count)]) == p
    }

    private func readInt(in bytes: [UInt8], from start: Int) -> Int? {
        var i = start
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
        var value = 0
        var digits = 0
        while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
            value = value * 10 + Int(bytes[i] - 0x30)
            digits += 1
            i += 1
        }
        return digits > 0 ? value : nil
    }

    /// Position des ersten "<<" und seines passenden ">>" (Anfang der beiden Zeichen).
    private func topLevelDictionary(in bytes: [UInt8]) -> (Int, Int)? {
        var i = 0
        while i + 1 < bytes.count, !(bytes[i] == 0x3C && bytes[i + 1] == 0x3C) { i += 1 }
        guard i + 1 < bytes.count else { return nil }
        let start = i
        var depth = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0x3C && bytes[i + 1] == 0x3C {
                depth += 1
                i += 2
            } else if bytes[i] == 0x3E && bytes[i + 1] == 0x3E {
                depth -= 1
                if depth == 0 { return (start, i) }
                i += 2
            } else {
                i += 1
            }
        }
        return nil
    }

    private func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var result: [String] = []
        for g in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: g), in: text) else { return nil }
            result.append(String(text[r]))
        }
        return result
    }

    private func firstInt(in text: String, pattern: String) -> Int? {
        guard let c = captures(in: text, pattern: pattern), let first = c.first else { return nil }
        return Int(first)
    }

    private func randomHex(_ byteCount: Int) -> String {
        var s = ""
        for _ in 0..<byteCount {
            let b = UInt8.random(in: 0...255)
            let h = String(b, radix: 16, uppercase: true)
            s += h.count == 1 ? "0" + h : h
        }
        return s
    }
}
