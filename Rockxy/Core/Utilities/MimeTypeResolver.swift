import Foundation

/// Shared MIME type detection from file extensions.
/// Used by both single-file and directory Map Local flows, and by the snapshot service.
enum MimeTypeResolver {
    // MARK: Internal

    /// Returns the MIME type for a file path based on its extension.
    static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return mimeTypes[ext] ?? "application/octet-stream"
    }

    /// Returns the MIME type for a URL based on its path extension.
    static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return mimeTypes[ext] ?? "application/octet-stream"
    }

    /// Infers a file extension from a Content-Type header value.
    /// Returns the extension without the leading dot, or nil if unknown.
    static func inferExtension(fromContentType contentType: String?) -> String? {
        guard let ct = contentType?.lowercased().components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces) else
        {
            return nil
        }
        return extensionsByMime[ct]
    }

    /// Infers a file extension from a transaction's response Content-Type or request URL.
    static func inferExtension(from transaction: HTTPTransaction) -> String? {
        if let ext = inferExtension(fromContentType: transaction.response?.headers.first(where: {
            $0.name.lowercased() == "content-type"
        })?.value) {
            return ext
        }
        let urlExt = transaction.request.url.pathExtension.lowercased()
        return urlExt.isEmpty ? nil : urlExt
    }

    // MARK: Private

    private static let mimeTypes: [String: String] = [
        "html": "text/html",
        "htm": "text/html",
        "css": "text/css",
        "js": "application/javascript",
        "mjs": "application/javascript",
        "json": "application/json",
        "xml": "application/xml",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "eot": "application/vnd.ms-fontobject",
        "pdf": "application/pdf",
        "txt": "text/plain",
        "csv": "text/csv",
        "mp4": "video/mp4",
        "webm": "video/webm",
        "mp3": "audio/mpeg",
        "ogg": "audio/ogg",
        "wav": "audio/wav",
        "zip": "application/zip",
        "gz": "application/gzip",
        "wasm": "application/wasm",
        "map": "application/json",
        "yaml": "application/yaml",
        "yml": "application/yaml",
        "ndjson": "application/x-ndjson",
        "avif": "image/avif",
        "m3u8": "application/vnd.apple.mpegurl",
        "md": "text/markdown",
        "tsv": "text/tab-separated-values",
    ]

    private static let extensionsByMime: [String: String] = [
        "text/html": "html",
        "text/css": "css",
        "application/javascript": "js",
        "application/json": "json",
        "application/xml": "xml",
        "image/svg+xml": "svg",
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/x-icon": "ico",
        "font/woff": "woff",
        "font/woff2": "woff2",
        "font/ttf": "ttf",
        "font/otf": "otf",
        "application/vnd.ms-fontobject": "eot",
        "application/pdf": "pdf",
        "text/plain": "txt",
        "text/csv": "csv",
        "video/mp4": "mp4",
        "video/webm": "webm",
        "audio/mpeg": "mp3",
        "audio/ogg": "ogg",
        "audio/wav": "wav",
        "application/zip": "zip",
        "application/gzip": "gz",
        "application/wasm": "wasm",
    ]
}
