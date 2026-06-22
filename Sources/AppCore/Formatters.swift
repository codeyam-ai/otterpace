import Foundation

// Pure presentation helpers shared by the Today dashboard components. Kept free
// of SwiftUI so they're straightforward to unit-test.

/// Group a whole number with locale thousands separators, e.g. 11240 -> "11,240".
func formatted(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// Compact "time since last movement" label: "now", "45m", "1h", "1h32m".
func movementLabel(_ minutes: Int) -> String {
    if minutes <= 0 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h\(m)m"
}

/// Render an ISO `yyyy-MM-dd` date as "EEE, MMM d" (e.g. "Mon, Jun 22").
/// Falls back to the raw string when it isn't a valid ISO date.
func prettyDate(_ iso: String) -> String {
    let inFmt = DateFormatter()
    inFmt.dateFormat = "yyyy-MM-dd"
    inFmt.locale = Locale(identifier: "en_US_POSIX")
    guard let d = inFmt.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "EEE, MMM d"
    out.locale = Locale(identifier: "en_US_POSIX")
    return out.string(from: d)
}
