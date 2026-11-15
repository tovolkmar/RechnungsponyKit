import Foundation

/// Umsatzsteuerkategorie einer Position (BT-151, UNTDID 5305), soweit die App sie anbietet.
public enum TaxCategory: String, Codable, CaseIterable, Sendable {
    /// Normalsatz oder ermäßigter Satz (Satz über 0 %)
    case standard = "S"
    /// Nullsatz: Steuersatz 0 %, ohne Befreiungsgrund
    case zeroRated = "Z"
    /// Steuerfrei: Satz 0 % mit Befreiungsgrund (BT-120)
    case exempt = "E"

    public var title: String {
        switch self {
        case .standard: "Mit Umsatzsteuer"
        case .zeroRated: "0 % (Nullsatz)"
        case .exempt: "Steuerfrei"
        }
    }

    /// Nur „Mit Umsatzsteuer“ hat einen frei wählbaren Satz
    public var hasRate: Bool { self == .standard }
    /// Steuerfreie Positionen brauchen einen Grund, der auf der Rechnung steht (BR-E-10)
    public var needsExemptionReason: Bool { self == .exempt }
}
