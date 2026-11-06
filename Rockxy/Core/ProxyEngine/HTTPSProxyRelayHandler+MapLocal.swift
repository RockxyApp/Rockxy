import Foundation
import NIOCore
import NIOHTTP1
import os

/// Same category as the main relay handler so the Map Local lines read identically to before
/// these serving paths moved out of `HTTPSProxyRelayHandler.swift`.
nonisolated(unsafe) private let mapLocalRelayLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "HTTPSProxyRelayHandler"
)

// MARK: - Map Local Serving

extension HTTPSProxyRelayHandler {
    /// Serves a single mapped file. The read is blocking and has no deadline — a target on a
    /// stale network mount or a spun-down disk waits in the kernel — so it runs on the Map Local
    /// file-I/O queue and only the response resumes on this channel's event loop.
    nonisolated func handleMapLocal(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        filePath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let promise = context.eventLoop.makePromise(of: Data?.self)
        MapLocalFileValidator.loadFileData(at: filePath) { promise.succeed($0) }
        promise.futureResult.whenSuccess { [weak self] data in
            // The client can disconnect (or the proxy stop) while the file is being read: a
            // late mapping must neither write to a dead channel nor start origin work for it.
            guard let self, context.channel.isActive else {
                return
            }
            guard let data else {
                // Missing / unreadable / oversized target — serve the origin instead of a
                // synthesized 404 so a broken mapping degrades to normal traffic.
                mapLocalRelayLogger.info("Map local file unavailable, falling back to origin")
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
                return
            }

            let outcome = MapLocalResponseResolver.resolve(
                fileData: data,
                actionStatusCode: statusCode,
                configuredHeaders: responseHeaders,
                inferredContentType: MimeTypeResolver.mimeType(for: filePath)
            )
            switch outcome {
            case let .serve(payload):
                self.sendMappedResponse(
                    context: context,
                    responseData: Self.mapLocalResponse(from: payload),
                    requestData: requestData,
                    callback: callback
                )
            case .fallbackToOrigin:
                // Invalid status or a malformed HTTP-message-looking file — forward the origin.
                mapLocalRelayLogger.info("Map local response invalid, falling back to origin")
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        }
    }

    /// Serves a file from a mapped directory. Resolution touches the filesystem (existence,
    /// containment, size, read), so it takes the same off-loop route as the single-file path.
    nonisolated func handleMapLocalDirectory(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        directoryPath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        matchContext: MapLocalMatchContext
    ) {
        let promise = context.eventLoop.makePromise(of: MapLocalDirectoryResolver.ResolvedFile?.self)
        MapLocalDirectoryResolver.resolve(
            requestURL: requestData.url.absoluteString,
            matchContext: matchContext,
            directoryPath: directoryPath
        ) { promise.succeed($0) }
        promise.futureResult.whenSuccess { [weak self] file in
            guard let self, context.channel.isActive else {
                return
            }
            guard let file else {
                // Unresolved / invalid target — fall back to the origin request.
                mapLocalRelayLogger.info("Map local directory unresolved, falling back to origin")
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
                return
            }

            let outcome = MapLocalResponseResolver.resolve(
                fileData: file.data,
                actionStatusCode: statusCode,
                configuredHeaders: responseHeaders,
                inferredContentType: file.mimeType
            )
            switch outcome {
            case let .serve(payload):
                self.sendMappedResponse(
                    context: context,
                    responseData: Self.mapLocalResponse(from: payload),
                    requestData: requestData,
                    callback: callback
                )
            case .fallbackToOrigin:
                mapLocalRelayLogger.info("Map local directory response invalid, falling back to origin")
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        }
    }

    /// Builds an `HTTPResponseData` from a resolved Map Local payload, deriving the standard
    /// reason phrase when the payload did not carry one. Shared with the single-file and
    /// directory serving paths so HTTP and HTTPS stay structurally identical.
    nonisolated private static func mapLocalResponse(
        from payload: MapLocalResponseResolver.Payload
    )
        -> HTTPResponseData
    {
        let message = payload.statusMessage ?? HTTPResponseStatus(statusCode: payload.statusCode).reasonPhrase
        return HTTPResponseData(
            statusCode: payload.statusCode,
            statusMessage: message,
            headers: MapLocalMarkerSetting.markedHeaders(payload.headers),
            body: payload.body
        )
    }
}
