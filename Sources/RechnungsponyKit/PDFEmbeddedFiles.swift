import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

/// Liest die eingebetteten Dateien (Names-Baum und /AF) aus einem PDF, z. B. das XML einer ZUGFeRD-Rechnung.
public enum PDFEmbeddedFiles {
    public struct File {
        public let name: String
        public let data: Data
    }

    public static func extract(from pdf: Data) -> [File] {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return [] }

        var files: [File] = []
        func add(_ file: File?) {
            guard let file, !files.contains(where: { $0.name == file.name && $0.data == file.data }) else { return }
            files.append(file)
        }

        // 1. Names → EmbeddedFiles (Namensbaum, ggf. mit Kids)
        var names: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names {
            var embedded: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &embedded), let embedded {
                walk(embedded, depth: 0, add: add)
            }
        }

        // 2. Zusätzlich /AF (Associated Files)
        var af: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(catalog, "AF", &af), let af {
            for index in 0..<CGPDFArrayGetCount(af) {
                var spec: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(af, index, &spec), let spec {
                    add(file(from: spec, fallbackName: "Anlage-\(index + 1)"))
                }
            }
        }
        return files
    }

    private static func walk(_ node: CGPDFDictionaryRef, depth: Int, add: (File?) -> Void) {
        guard depth < 8 else { return }
        var array: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &array), let array {
            let count = CGPDFArrayGetCount(array)
            var index = 0
            while index + 1 < count {
                var keyString: CGPDFStringRef?
                var spec: CGPDFDictionaryRef?
                var fallback = "Anlage"
                if CGPDFArrayGetString(array, index, &keyString), let keyString,
                   let text = CGPDFStringCopyTextString(keyString) as String? {
                    fallback = text
                }
                if CGPDFArrayGetDictionary(array, index + 1, &spec), let spec {
                    add(file(from: spec, fallbackName: fallback))
                }
                index += 2
            }
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kids {
            for index in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, index, &kid), let kid {
                    walk(kid, depth: depth + 1, add: add)
                }
            }
        }
    }

    private static func file(from spec: CGPDFDictionaryRef, fallbackName: String) -> File? {
        var ef: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(spec, "EF", &ef), let ef else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(ef, "F", &stream) || CGPDFDictionaryGetStream(ef, "UF", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return nil }

        var name = fallbackName
        for key in ["UF", "F"] {
            var string: CGPDFStringRef?
            if CGPDFDictionaryGetString(spec, key, &string), let string,
               let text = CGPDFStringCopyTextString(string) as String?, !text.isEmpty {
                name = text
                break
            }
        }
        return File(name: name, data: cfData as Data)
    }
}
#else
public enum PDFEmbeddedFiles {
    public struct File {
        public let name: String
        public let data: Data
    }
    public static func extract(from pdf: Data) -> [File] { [] }
}
#endif
