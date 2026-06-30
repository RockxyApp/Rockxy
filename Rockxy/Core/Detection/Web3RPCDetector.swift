import Foundation

// MARK: - Web3RPCDetector

/// Bounded detector for visible Web3 JSON-RPC carried over captured HTTP traffic.
enum Web3RPCDetector {
    // MARK: Internal

    static let maxPayloadBytes = 1_048_576

    static func detect(request: HTTPRequestData, response: HTTPResponseData? = nil) -> Web3RPCInfo? {
        guard request.method.caseInsensitiveCompare("CONNECT") != .orderedSame,
              let requestBody = request.body,
              !requestBody.isEmpty,
              requestBody.count <= maxPayloadBytes,
              let requestRoot = parseJSON(requestBody) else
        {
            return nil
        }

        let requests = parseRequests(from: requestRoot)
        let web3Requests = requests.filter { isWeb3Method($0.method) }
        guard let primary = web3Requests.first else {
            return nil
        }

        let responses = parseResponses(from: response?.body)
        let primaryResponse = responseEntry(matching: primary.id, in: responses) ?? responses.first
        let batch = makeBatchSummary(requestRoot: requestRoot, requests: requests, web3Requests: web3Requests, responses: responses)
        let error = primaryResponse?.error ?? responses.compactMap(\.error).first
        let family = family(for: primary.method)

        return Web3RPCInfo(
            family: family,
            providerHost: request.host,
            method: batch == nil ? primary.method : nil,
            requestID: batch == nil ? primary.id : nil,
            batch: batch,
            error: error,
            chainHint: chainHint(method: primary.method, response: primaryResponse),
            transactionHash: transactionHash(method: primary.method, request: primary, response: primaryResponse),
            blockIdentifier: blockIdentifier(method: primary.method, request: primary, response: primaryResponse),
            requestPayloadSize: request.body?.count,
            responsePayloadSize: response?.body?.count
        )
    }

    // MARK: Private

    private struct RPCRequest {
        let method: String
        let id: String?
        let params: Any?
    }

    private struct RPCResponse {
        let id: String?
        let result: Any?
        let error: Web3RPCError?
    }

    private static let evmMethodPrefixes = [
        "eth_",
        "net_",
        "web3_",
        "debug_",
        "trace_",
        "txpool_",
        "personal_",
        "wallet_",
        "evm_",
        "hardhat_",
        "anvil_",
        "ots_",
        "erigon_",
        "parity_",
        "bor_",
        "zks_",
        "optimism_",
    ]

    private static let solanaMethods: Set<String> = [
        "getAccountInfo",
        "getBalance",
        "getBlock",
        "getBlockHeight",
        "getBlockProduction",
        "getBlockTime",
        "getBlocks",
        "getClusterNodes",
        "getEpochInfo",
        "getFeeForMessage",
        "getHealth",
        "getIdentity",
        "getLatestBlockhash",
        "getLeaderSchedule",
        "getMinimumBalanceForRentExemption",
        "getMultipleAccounts",
        "getProgramAccounts",
        "getRecentPerformanceSamples",
        "getSignaturesForAddress",
        "getSignatureStatuses",
        "getSlot",
        "getSupply",
        "getTokenAccountBalance",
        "getTokenAccountsByOwner",
        "getTransaction",
        "getTransactionCount",
        "getVersion",
        "requestAirdrop",
        "sendTransaction",
        "simulateTransaction",
    ]

    private static func parseJSON(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    private static func parseRequests(from root: Any) -> [RPCRequest] {
        if let object = root as? [String: Any], let request = parseRequestObject(object) {
            return [request]
        }
        if let array = root as? [[String: Any]] {
            return array.compactMap(parseRequestObject)
        }
        return []
    }

    private static func parseRequestObject(_ object: [String: Any]) -> RPCRequest? {
        guard let method = object["method"] as? String else {
            return nil
        }
        return RPCRequest(
            method: method,
            id: rpcIDDescription(object["id"]),
            params: object["params"]
        )
    }

    private static func parseResponses(from body: Data?) -> [RPCResponse] {
        guard let body, !body.isEmpty, body.count <= maxPayloadBytes, let root = parseJSON(body) else {
            return []
        }
        if let object = root as? [String: Any] {
            return [parseResponseObject(object)]
        }
        if let array = root as? [[String: Any]] {
            return array.map(parseResponseObject)
        }
        return []
    }

    private static func parseResponseObject(_ object: [String: Any]) -> RPCResponse {
        RPCResponse(
            id: rpcIDDescription(object["id"]),
            result: object["result"],
            error: parseError(object["error"])
        )
    }

    private static func parseError(_ value: Any?) -> Web3RPCError? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        let code = intValue(object["code"])
        let message = object["message"] as? String
        guard code != nil || message != nil else {
            return nil
        }
        return Web3RPCError(code: code, message: message)
    }

    private static func makeBatchSummary(
        requestRoot: Any,
        requests: [RPCRequest],
        web3Requests: [RPCRequest],
        responses: [RPCResponse]
    )
        -> Web3RPCBatchSummary?
    {
        guard requestRoot is [Any] else {
            return nil
        }

        let methods = Array(web3Requests.map(\.method).prefix(6))
        return Web3RPCBatchSummary(
            requestCount: requests.count,
            web3RequestCount: web3Requests.count,
            responseCount: responses.isEmpty ? nil : responses.count,
            errorCount: responses.compactMap(\.error).count,
            methods: methods
        )
    }

    private static func responseEntry(matching id: String?, in responses: [RPCResponse]) -> RPCResponse? {
        guard let id else {
            return nil
        }
        return responses.first { $0.id == id }
    }

    private static func isWeb3Method(_ method: String) -> Bool {
        evmMethodPrefixes.contains { method.hasPrefix($0) } || solanaMethods.contains(method)
    }

    private static func family(for method: String) -> Web3RPCFamily {
        solanaMethods.contains(method) ? .solana : .evm
    }

    private static func chainHint(method: String, response: RPCResponse?) -> Web3RPCChainHint? {
        if method == "eth_chainId", let chainID = stringValue(response?.result) {
            return Web3RPCChainHint(chainID: chainID)
        }
        return nil
    }

    private static func transactionHash(method: String, request: RPCRequest, response: RPCResponse?) -> String? {
        if method == "eth_sendRawTransaction", let hash = stringValue(response?.result), looksLikeHash(hash) {
            return hash
        }
        if ["eth_getTransactionByHash", "eth_getTransactionReceipt"].contains(method),
           let hash = arrayValue(request.params)?.first.flatMap(stringValue),
           looksLikeHash(hash)
        {
            return hash
        }
        if method == "eth_getLogs",
           let firstLog = arrayValue(response?.result)?.first as? [String: Any],
           let hash = firstLog["transactionHash"].flatMap(stringValue),
           looksLikeHash(hash)
        {
            return hash
        }
        if method == "sendTransaction", let signature = stringValue(response?.result), !signature.isEmpty {
            return signature
        }
        return nil
    }

    private static func blockIdentifier(method: String, request: RPCRequest, response: RPCResponse?) -> String? {
        if ["eth_call", "eth_estimateGas"].contains(method),
           let params = arrayValue(request.params),
           params.count > 1
        {
            return stringValue(params[1])
        }

        if method == "eth_getLogs",
           let filter = arrayValue(request.params)?.first as? [String: Any]
        {
            if let blockHash = filter["blockHash"].flatMap(stringValue) {
                return blockHash
            }
            let fromBlock = filter["fromBlock"].flatMap(stringValue)
            let toBlock = filter["toBlock"].flatMap(stringValue)
            if let fromBlock, let toBlock {
                return "\(fromBlock)...\(toBlock)"
            }
            return fromBlock ?? toBlock
        }

        if ["eth_getBlockByHash", "eth_getBlockByNumber"].contains(method),
           let block = arrayValue(request.params)?.first.flatMap(stringValue)
        {
            return block
        }

        if let resultObject = response?.result as? [String: Any],
           let blockNumber = resultObject["blockNumber"].flatMap(stringValue)
        {
            return blockNumber
        }

        if method == "eth_getLogs",
           let firstLog = arrayValue(response?.result)?.first as? [String: Any],
           let blockNumber = firstLog["blockNumber"].flatMap(stringValue)
        {
            return blockNumber
        }

        return nil
    }

    private static func rpcIDDescription(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.stringValue
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private static func looksLikeHash(_ value: String) -> Bool {
        guard value.hasPrefix("0x"), value.count == 66 else {
            return false
        }
        return value.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
