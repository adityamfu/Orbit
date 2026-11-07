import Foundation

/// Free Personal Team builds expire after 7 days; the date lives in the bundled provisioning profile.
public enum BuildInfo {
    /// nil on the simulator (no profile) or if the profile can't be read.
    public static var expirationDate: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(fromProfile: data)
    }

    /// The profile is a signed (CMS) blob with a plain XML plist inside; cut the plist out and read it.
    public static func expirationDate(fromProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil
              ) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Whole days left, rounded down; negative once expired.
    public static func daysRemaining(until expiry: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: now, to: expiry).day ?? 0
    }

    public static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
