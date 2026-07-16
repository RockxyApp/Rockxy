import Foundation

extension MainContentCoordinator {
    func importNearbyTransfer(
        _ session: RockxyNearbyTransferSession,
        deviceName: String
    )
        async throws
    {
        let importedTransactions = try session.transactions.map(Self.makeNearbyTransaction)
        guard !importedTransactions.isEmpty else {
            throw RockxyNearbyTransferError.emptyTransfer
        }

        let workspaceTitle = String(session.metadata.title.prefix(80))
        let destinationWorkspace: WorkspaceState = if workspaceStore.canCreateWorkspace {
            workspaceStore.createWorkspace(
                title: workspaceTitle.isEmpty ? String(localized: "Rockxy iOS") : workspaceTitle
            )
        } else {
            activeWorkspace
        }

        for transaction in importedTransactions {
            transaction.sequenceNumber = nextSequenceNumber
            nextSequenceNumber += 1
            transactions.append(transaction)
            updateDomainGroupingIndex(for: transaction, in: destinationWorkspace)
            updateAppNodes(for: transaction, in: destinationWorkspace)
        }
        refreshDomainTree(for: destinationWorkspace)
        destinationWorkspace.filteredTransactions = importedTransactions.filter { !$0.isTLSFailure }
        destinationWorkspace.lastDeriveWasAppendOnly = false
        deriveFilteredRows(for: destinationWorkspace)
        rebuildObservedDomainsByApp()
        headerColumnStore.updateDiscoveredHeaders(from: transactions)
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)

        let safeDeviceName = String(deviceName.prefix(80))
        sessionProvenance = SessionProvenance(
            fileName: "Nearby • \(safeDeviceName)",
            transactionCount: importedTransactions.count,
            logEntryCount: 0,
            importedAt: Date()
        )
        activeToast = ToastMessage(
            style: .success,
            text: String(localized: "Added \(importedTransactions.count) iOS requests from \(safeDeviceName)")
        )
    }

    private static func makeNearbyTransaction(
        _ transaction: RockxyNearbyTransferSession.Transaction
    )
        throws -> HTTPTransaction
    {
        guard let method = transaction.request.method,
              !method.isEmpty,
              let urlString = transaction.request.url,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else
        {
            throw RockxyNearbyTransferError.invalidTransaction
        }

        let requestHeaders = transaction.request.headers.map {
            HTTPHeader(name: String($0.key.prefix(1_024)), value: String($0.value.prefix(32_768)))
        }
        let requestBody = bodyData(transaction.request.body)
        let request = HTTPRequestData(
            method: String(method.prefix(32)),
            url: url,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: requestBody,
            contentType: ContentTypeDetector.detect(headers: requestHeaders, body: requestBody)
        )

        let response: HTTPResponseData? = if let message = transaction.response,
                                             let statusCode = message.statusCode,
                                             (100 ... 599).contains(statusCode)
        {
            makeNearbyResponse(message, statusCode: statusCode)
        } else {
            nil
        }

        let result = HTTPTransaction(
            timestamp: nearbyTimestamp(transaction.timestamp),
            request: request,
            response: response,
            state: .completed,
            timingInfo: nearbyTiming(transaction.timing)
        )
        result.clientApp = String((transaction.clientApp ?? "Rockxy iOS").prefix(120))
        if let durationMs = transaction.timing?.durationMs, durationMs >= 0 {
            result.measuredDuration = durationMs / 1_000
        }
        return result
    }

    private static func makeNearbyResponse(
        _ message: RockxyNearbyTransferSession.Transaction.Message,
        statusCode: Int
    )
        -> HTTPResponseData
    {
        let headers = message.headers.map {
            HTTPHeader(name: String($0.key.prefix(1_024)), value: String($0.value.prefix(32_768)))
        }
        let body = bodyData(message.body)
        return HTTPResponseData(
            statusCode: statusCode,
            statusMessage: HTTPURLResponse.localizedString(forStatusCode: statusCode),
            headers: headers,
            body: body,
            contentType: ContentTypeDetector.detect(headers: headers, body: body)
        )
    }

    private static func bodyData(
        _ body: RockxyNearbyTransferSession.Transaction.Message.Body?
    )
        -> Data?
    {
        guard let content = body?.content, !content.isEmpty else {
            return nil
        }
        return Data(content.prefix(2 * 1_024 * 1_024).utf8)
    }

    private static func nearbyTiming(
        _ timing: RockxyNearbyTransferSession.Transaction.Timing?
    )
        -> TimingInfo?
    {
        guard let timing else {
            return nil
        }
        return TimingInfo(
            dnsLookup: max(0, timing.dnsMs ?? 0) / 1_000,
            tcpConnection: max(0, timing.connectMs ?? 0) / 1_000,
            tlsHandshake: max(0, timing.tlsMs ?? 0) / 1_000,
            timeToFirstByte: max(0, timing.ttfbMs ?? 0) / 1_000,
            contentTransfer: max(0, timing.transferMs ?? timing.durationMs) / 1_000
        )
    }

    private static func nearbyTimestamp(_ value: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? Date()
    }
}
