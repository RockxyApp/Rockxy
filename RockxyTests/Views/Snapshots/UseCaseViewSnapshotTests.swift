import AppKit
import SwiftUI
@testable import Rockxy
import Testing

// MARK: - UseCaseViewSnapshotTests

/// Renders new inspector and tool views offscreen to PNG for visual review. Runs only
/// when `ROCKXY_RENDER_SNAPSHOTS` names an output directory, e.g.
/// `TEST_RUNNER_ROCKXY_RENDER_SNAPSHOTS=/tmp/shots xcodebuild … test`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ROCKXY_RENDER_SNAPSHOTS"] != nil))
struct UseCaseViewSnapshotTests {
    // MARK: Internal

    @Test("Multipart inspector")
    func multipart() async throws {
        var body = Data()
        body.append(Data("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nVacation photo\r\n".utf8))
        body.append(Data(
            "--B\r\nContent-Disposition: form-data; name=\"meta\"; filename=\"meta.json\"\r\nContent-Type: application/json\r\n\r\n{\"tags\":[\"beach\"]}\r\n"
                .utf8
        ))
        body.append(Data("--B--\r\n".utf8))
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/upload")
        transaction.request = HTTPRequestData(
            method: "POST",
            url: transaction.request.url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "multipart/form-data; boundary=B")],
            body: body
        )
        try await render(MultipartInspectorView(transaction: transaction), name: "multipart", size: CGSize(width: 640, height: 420))
    }

    @Test("Server-sent events inspector")
    func serverSentEvents() async throws {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/v1/chat/stream")
        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            body: Data("event: delta\ndata: {\"text\":\"Hel\"}\n\nevent: delta\ndata: {\"text\":\"lo\"}\n\ndata: [DONE]\n\n".utf8)
        )
        try await render(ServerSentEventsInspectorView(transaction: transaction), name: "sse", size: CGSize(width: 640, height: 420))
    }

    @Test("JSON body filtered with jq")
    func jqFilter() async throws {
        let body = Data(#"""
        {"posts":[{"id":1,"likes":4,"user":{"name":"ana"}},{"id":2,"likes":42,"user":{"name":"bo"}},
        {"id":3,"likes":17,"user":{"name":"cy"}}],"page":1}
        """#.utf8)
        try await render(
            JSONTreeView(data: body, filterMode: .jq, query: ".posts[] | select(.likes > 10) | {name: .user.name, likes}"),
            name: "jq-filter",
            size: CGSize(width: 560, height: 360)
        )
        try await render(
            JSONTreeView(data: body, filterMode: .jq, query: ".posts[] | .nope("),
            name: "jq-error",
            size: CGSize(width: 560, height: 200)
        )
    }

    @Test("Command palette")
    func commandPalette() async throws {
        try await render(
            CommandPaletteView(commands: CommandPaletteCatalog.commands) { _ in },
            name: "command-palette",
            size: CGSize(width: 560, height: 380)
        )
    }

    @Test("Reverse proxy window")
    func reverseProxy() async throws {
        try await render(ReverseProxyWindowView(), name: "reverse-proxy", size: CGSize(width: 860, height: 420))
    }

    @Test("SOCKS5 listener settings")
    func socksSettings() async throws {
        try await render(SOCKSListenerSettingsSection().padding(), name: "socks-settings", size: CGSize(width: 560, height: 200))
    }

    @Test("Access Control settings")
    func accessControl() async throws {
        let defaults = UserDefaults(suiteName: "snapshot-\(UUID().uuidString)") ?? .standard
        let settings = RemoteAccessSettings(defaults: defaults, gate: RemoteAccessGate())
        settings.setMode(.listedDevices)
        settings.addEntry("192.168.1.20")
        settings.addEntry("10.0.0.0/8")
        settings.recordRefused("192.168.1.44")
        try await render(
            RemoteAccessSettingsSection(listensOnlyOnLocalhost: false, settings: settings).padding(),
            name: "access-control",
            size: CGSize(width: 560, height: 360)
        )
    }

    @Test("DNS Spoofing window")
    func dnsSpoofing() async throws {
        try await render(DNSSpoofingWindowView(), name: "dns-spoofing", size: CGSize(width: 720, height: 400))
    }

    @Test("TLS key log window")
    func tlsKeyLog() async throws {
        try await render(TLSKeyLogWindowView(), name: "tls-key-log", size: CGSize(width: 520, height: 320))
    }

    @Test("Advanced filter bar")
    func advancedFilterBar() async throws {
        let rules = [
            FilterRule(field: .all, filterOperator: .contains, value: "token_expired"),
            FilterRule(connector: .or, field: .graphQLOperation, filterOperator: .is, value: "GetUser"),
        ]
        let store = FilterPresetStore(
            userDefaults: UserDefaults(suiteName: "snapshot-\(UUID().uuidString)") ?? .standard,
            storageKey: "presets"
        )
        try await render(
            AdvancedFilterBar(rules: .constant(rules), presetStore: store),
            name: "advanced-filter-bar",
            size: CGSize(width: 900, height: 110)
        )
    }

    @Test("WebSocket inspector with JSON frames")
    func webSocketInspector() async throws {
        let transaction = TestFixtures.makeTransaction(url: "https://chat.example.com/socket")
        transaction.webSocketConnection = WebSocketConnection(
            upgradeRequest: transaction.request,
            frames: [
                WebSocketFrameData(direction: .sent, opcode: .text, payload: Data(#"{"type":"join","room":"lobby"}"#.utf8)),
                WebSocketFrameData(direction: .received, opcode: .text, payload: Data(#"{"type":"message","text":"hi"}"#.utf8)),
            ]
        )
        try await render(WebSocketInspectorView(transaction: transaction), name: "websocket", size: CGSize(width: 720, height: 520))
    }

    @Test("Status bar with active tools")
    func statusBar() async throws {
        let rules = [
            ProxyRule(name: "Mock", matchCondition: RuleMatchCondition(urlPattern: ".*"), action: .mapLocal(filePath: "/tmp/a.json")),
            ProxyRule(
                name: "Offline",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .networkCondition(preset: .offline, delayMs: 0)
            ),
        ]
        try await render(
            StatusBarView(totalCount: 1_204, selectedCount: 0, isProxyRunning: true, activeRules: rules),
            name: "status-bar",
            size: CGSize(width: 1_100, height: 36)
        )
    }

    @Test("Request and response inspectors show conditional tabs")
    func inspectorTabs() async throws {
        let coordinator = MainContentCoordinator()
        let store = PreviewTabStore(defaults: UserDefaults(suiteName: "snapshot-\(UUID().uuidString)") ?? .standard)
        let upload = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/upload")
        upload.request = HTTPRequestData(
            method: "POST",
            url: upload.request.url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "multipart/form-data; boundary=B")],
            body: Data("--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--B--\r\n".utf8)
        )
        upload.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            body: Data("data: hello\n\n".utf8)
        )
        try await render(
            HStack(spacing: 0) {
                RequestInspectorView(transaction: upload, coordinator: coordinator, previewTabStore: store)
                Divider()
                ResponseInspectorView(transaction: upload, coordinator: coordinator, previewTabStore: store)
            },
            name: "inspector-tabs",
            size: CGSize(width: 1_280, height: 300)
        )
    }

    // MARK: Private

    private func render(_ view: some View, name: String, size: CGSize) async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["ROCKXY_RENDER_SNAPSHOTS"])
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.wantsLayer = true
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let `.task` loaders (parsing off the main thread) finish before capturing.
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let scale: CGFloat = 2
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        CGRect(origin: .zero, size: size).fill()
        if let layer = host.layer {
            // Core Animation draws top-down; flip into the bitmap's bottom-up space.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            layer.render(in: context.cgContext)
        } else {
            host.displayIgnoringOpacity(host.bounds, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try png.write(to: url)
    }
}
