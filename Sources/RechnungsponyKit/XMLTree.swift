import Foundation

/// Kleiner XML-Baum für den E-Rechnung-Leser. Namensräume werden ignoriert: `ram:ID` heißt hier `ID`.
final class XMLElementNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLElementNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XMLElementNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [XMLElementNode] { children.filter { $0.name == name } }

    /// Pfad aus Elementnamen, getrennt durch "/", z. B. `ExchangedDocument/IssueDateTime/DateTimeString`
    func node(_ path: String) -> XMLElementNode? {
        var current: XMLElementNode? = self
        for part in path.split(separator: "/") {
            current = current?.child(String(part))
            if current == nil { return nil }
        }
        return current
    }

    /// Text des Elements am Pfad, ohne Leerraum an den Rändern; nil, wenn leer oder nicht vorhanden
    func string(_ path: String) -> String? {
        guard let value = node(path)?.text.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum XMLTree {
    static func parse(_ data: Data) throws -> XMLElementNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw EInvoiceReaderError.invalidXML(parser.parserError?.localizedDescription ?? "unbekannter Fehler")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLElementNode?
        var stack: [XMLElementNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict {
                attributes[key.split(separator: ":").last.map(String.init) ?? key] = value
            }
            let node = XMLElementNode(name: local, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }
    }
}
