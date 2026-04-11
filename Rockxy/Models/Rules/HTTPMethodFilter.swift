import Foundation

// MARK: - HTTPMethodFilter

/// Shared HTTP method filter for rule editors. `.any` matches all methods.
enum HTTPMethodFilter: String, CaseIterable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"

    // MARK: Internal

    /// Returns the method string for rule matching, or `nil` for `.any`.
    var methodValue: String? {
        self == .any ? nil : rawValue
    }
}
