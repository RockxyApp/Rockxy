import AppKit

// Symbol images the request table draws on every cell configuration.

// MARK: - RequestTableSymbolCache

/// Builds each table symbol once. The SSL column and the status dot each constructed a
/// fresh `NSImage(systemSymbolName:)` per cell per reload, from a set of four names. The
/// image carries no per-row state (size comes from the image view's symbol configuration,
/// color from its tint), so one instance serves every row.
///
/// Main-thread only, like the cell configuration that calls it.
enum RequestTableSymbolCache {
    // MARK: Internal

    /// Symbol images constructed since launch, by cache key. Counted work for tests.
    private(set) static var constructionCounts: [String: Int] = [:]

    static func image(systemSymbolName name: String, accessibilityDescription: String? = nil) -> NSImage? {
        let key = "\(name)|\(accessibilityDescription ?? "")"
        if let cached = images[key] {
            return cached
        }
        constructionCounts[key, default: 0] += 1
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        images[key] = image
        return image
    }

    /// The "modified by a rule" marker, configured for a point size. Keyed by size because
    /// the configured copy is what the attachment holds.
    static func configuredImage(
        systemSymbolName name: String,
        accessibilityDescription: String,
        pointSize: CGFloat,
        weight: NSFont.Weight
    )
        -> NSImage?
    {
        let key = "\(name)|\(accessibilityDescription)|\(pointSize)|\(weight.rawValue)"
        if let cached = images[key] {
            return cached
        }
        guard let base = image(systemSymbolName: name, accessibilityDescription: accessibilityDescription),
              let configured = base.withSymbolConfiguration(
                  NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
              ) else
        {
            return nil
        }
        images[key] = configured
        return configured
    }

    // MARK: Private

    private static var images: [String: NSImage] = [:]
}
