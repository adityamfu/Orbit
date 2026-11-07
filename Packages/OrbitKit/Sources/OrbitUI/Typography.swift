import SwiftUI

/// Inter Tight styles (DESIGN.md §3.2). Plain text uses system fonts (`.body`, `.subheadline`, …).
/// All scale with Dynamic Type via `relativeTo:`.
public enum Typography {
    /// Screen titles. Pair with `.tracking(-0.6)`.
    public static var largeTitle: Font { .custom("InterTight-ExtraBold", size: 34, relativeTo: .largeTitle) }
    /// Section titles ("Dompet", "Rutinitas").
    public static var section: Font { .custom("InterTight-Bold", size: 22, relativeTo: .title2) }
    /// Today stat tiles. Pair with `.tracking(-1.5)`.
    public static var statHero: Font { .custom("InterTight-ExtraBold", size: 64, relativeTo: .largeTitle).monospacedDigit() }
    /// Balances, quick-add amount.
    public static var amountHero: Font { .custom("InterTight-ExtraBold", size: 44, relativeTo: .largeTitle).monospacedDigit() }
    /// Amounts in lists, KPIs, small numbers.
    public static var metric: Font { .custom("InterTight-Bold", size: 17, relativeTo: .body).monospacedDigit() }
}
