import Foundation

extension Invoice {
    /// Rechnungen an Behörden (Käuferreferenz ist eine Leitweg-ID, geprüft mit `LeitwegID`)
    /// gehen als XRechnung hinaus, alle anderen als ZUGFeRD.
    public var preferredProfile: EInvoiceProfile {
        LeitwegID.looksLike(buyerReference ?? "") ? .xrechnung : .zugferdEN16931
    }
}
