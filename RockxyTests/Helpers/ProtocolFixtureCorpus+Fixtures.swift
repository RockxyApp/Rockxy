import Foundation

// MARK: - Corpus Smoke Fixtures

extension ProtocolFixture {
    static let commonTraceability = ProtocolFixtureTraceability(
        parentIssue: 176,
        childIssues: [186, 187, 194, 195],
        futureIssues: [143, 144, 145, 146, 177, 178, 179, 180]
    )

    static let httpJSONSmoke = ProtocolFixture(
        id: "foundation.http-json.redaction-smoke",
        title: "Ordinary JSON request with synthetic redaction candidate",
        family: .ordinaryHTTP,
        scenarioTags: ["http", "json", "redaction-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://api.example.com/v1/debug-smoke",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"request_id":"fixture-request","api_key":"synthetic-api-key"}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://api.example.com/v1/debug-smoke",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"ok":true,"request_id":"fixture-request"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["http", "json"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["api_key"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["request_id", "ok"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["JSON"],
                optionalColumns: ["content": "JSON"],
                inspectorTabs: ["Headers", "JSON", "Raw"],
                warningStates: [],
                exportSummaryFields: ["method", "host", "status", "redacted_fields"],
                mcpSummaryFields: ["method", "url", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let aiSSEContractSmoke = ProtocolFixture(
        id: "foundation.ai-sse.contract-smoke",
        title: "AI streaming response with synthetic tool call",
        family: .ai,
        scenarioTags: ["ai", "sse", "streaming", "tool-call", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Authorization", value: "Bearer synthetic-ai-token"),
                    ],
                    body: #"{"model":"synthetic-model","input":"[SYNTHETIC_PROMPT]","tool_choice":"auto"}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")],
                    body: nil
                ),
                streamEvents: [
                    .init(event: "response.created", data: #"{"id":"resp_fixture","model":"synthetic-model"}"#),
                    .init(event: "response.tool_call.delta", data: #"{"name":"lookup_order","arguments":"{\"order_id\":\"fixture-order\"}"}"#),
                    .init(event: "response.completed", data: #"{"id":"resp_fixture","status":"completed"}"#),
                ]
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["ai", "streaming", "tool_call", "model_request"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["Authorization", "input", "tool_choice", "arguments"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["model", "status"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["AI", "Stream"],
                optionalColumns: ["protocol": "AI", "streaming": "true"],
                inspectorTabs: ["AI", "Stream", "Tool Calls", "Raw"],
                warningStates: ["prompt_redaction_candidate", "tool_payload_redaction_candidate"],
                exportSummaryFields: ["model", "stream_event_count", "tool_call_count", "redacted_fields"],
                mcpSummaryFields: ["model", "status", "streaming", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let aiAnthropicSSEContractSmoke = ProtocolFixture(
        id: "ai.anthropic-sse.tool-use-contract",
        title: "Anthropic-style SSE stream with synthetic tool use",
        family: .ai,
        scenarioTags: ["ai", "anthropic", "sse", "streaming", "tool-call", "issue-188"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/messages",
                    headers: [
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "X-API-Key", value: "synthetic-ai-token"),
                    ],
                    body: #"{"model":"synthetic-claude","messages":[{"role":"user","content":"[SYNTHETIC_PROMPT]"}],"tools":[{"name":"lookup_fixture"}]}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/messages",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")]
                ),
                streamEvents: [
                    .init(event: "message_start", data: #"{"message":{"id":"msg_fixture","model":"synthetic-claude"}}"#),
                    .init(event: "content_block_start", data: #"{"type":"tool_use","name":"lookup_fixture","input":{}}"#),
                    .init(event: "content_block_delta", data: #"{"partial_json":"{\"query\":\"synthetic"}}"#),
                    .init(event: "content_block_delta", data: #"{"partial_json":" context\"}"}"#),
                    .init(event: "message_stop", data: #"{"stop_reason":"tool_use"}"#),
                ]
            )
        ]),
        expected: aiStreamingExpectations(
            hints: ["ai", "streaming", "tool_call", "anthropic_style", "model_request"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([188])
    )

    static let aiInterruptedToolCallContractSmoke = ProtocolFixture(
        id: "ai.openai-sse.interrupted-tool-call",
        title: "OpenAI-style stream with interrupted partial tool arguments",
        family: .ai,
        scenarioTags: ["ai", "openai", "sse", "streaming", "tool-call", "interrupted", "malformed", "issue-188"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [.init(name: "Authorization", value: "Bearer synthetic-ai-token")],
                    body: #"{"model":"synthetic-model","input":"[SYNTHETIC_PROMPT]","stream":true}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")]
                ),
                streamEvents: [
                    .init(event: "response.tool_call.delta", data: #"{"arguments":"{\"order_id\":\"fixture-""#),
                    .init(event: nil, data: "not-json-stream-event"),
                ]
            )
        ]),
        expected: aiStreamingExpectations(
            hints: ["ai", "streaming", "tool_call", "interrupted", "malformed", "fallback"],
            fallback: "Show bounded stream fallback and mark partial tool arguments as redaction candidates."
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: issueTraceability([188, 193])
    )

    static let aiProviderErrorNoUsageContractSmoke = ProtocolFixture(
        id: "ai.provider-error.no-usage-summary",
        title: "AI provider error stream ending without final usage",
        family: .ai,
        scenarioTags: ["ai", "sse", "provider-error", "no-usage-summary", "issue-188"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [.init(name: "Authorization", value: "Bearer synthetic-ai-token")],
                    body: #"{"model":"synthetic-model","input":"[SYNTHETIC_PROMPT]","stream":true}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 429,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")]
                ),
                streamEvents: [
                    .init(event: "error", data: #"{"type":"rate_limit_error","message":"synthetic provider error"}"#),
                ]
            )
        ]),
        expected: aiStreamingExpectations(
            hints: ["ai", "provider_error", "streaming", "missing_usage_summary"],
            fallback: "Summarize provider error without requiring a final usage chunk."
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([188])
    )

    static let aiEmbeddingContractSmoke = ProtocolFixture(
        id: "ai.embedding.vector-search-contract",
        title: "Embedding request followed by vector-search response",
        family: .ai,
        scenarioTags: ["ai", "embeddings", "vector-search", "retrieval", "issue-189"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://vector.example.com/v1/embeddings",
                    headers: [.init(name: "Authorization", value: "Bearer synthetic-vector-token")],
                    body: #"{"model":"synthetic-embedding-model","input":["synthetic document chunk"]}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://vector.example.com/v1/embeddings",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"data":[{"embedding":[0.01,0.02,0.03],"index":0}],"usage":{"total_tokens":3}}"#
                )
            ),
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://vector.example.com/v1/search",
                    body: #"{"query_embedding":[0.01,0.02,0.03],"top_k":2,"namespace":"synthetic-space"}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://vector.example.com/v1/search",
                    statusCode: 200,
                    body: #"{"matches":[{"id":"doc-fixture-1","score":0.91,"snippet":"public synthetic snippet"}]}"#
                )
            )
        ]),
        expected: aiRetrievalExpectations(
            hints: ["ai", "embedding", "vector_search", "retrieval"],
            warnings: ["retrieved_context_redaction_candidate"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([189])
    )

    static let aiRAGContractSmoke = ProtocolFixture(
        id: "ai.rag.synthetic-context-contract",
        title: "RAG flow with public and sensitive synthetic context",
        family: .ai,
        scenarioTags: ["ai", "rag", "retrieval", "sensitive-context", "model-call", "issue-189"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [.init(name: "Authorization", value: "Bearer synthetic-ai-token")],
                    body: #"""
                    {
                      "model": "synthetic-model",
                      "input": [
                        {"role": "system", "content": "Use retrieved context"},
                        {"role": "user", "content": "[SYNTHETIC_PROMPT]"},
                        {"role": "tool", "content": "public synthetic snippet; fake-account-id fixture-account"}
                      ]
                    }
                    """#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 200,
                    body: #"{"id":"resp_rag_fixture","output_text":"synthetic answer"}"#
                )
            )
        ]),
        expected: aiRetrievalExpectations(
            hints: ["ai", "rag", "retrieved_context", "model_request"],
            warnings: ["retrieved_context_redaction_candidate", "prompt_redaction_candidate"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([189])
    )

    static let aiMalformedRetrievalContractSmoke = ProtocolFixture(
        id: "ai.embedding.malformed-vector-payload",
        title: "Malformed embedding/vector payload with fallback",
        family: .ai,
        scenarioTags: ["ai", "embeddings", "vector-search", "malformed", "fallback", "issue-189"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://vector.example.com/v1/search",
                    body: #"{"query_embedding":[0.01,"unterminated""#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://vector.example.com/v1/search",
                    statusCode: 400,
                    body: #"{"error":"synthetic malformed vector payload"}"#
                )
            )
        ]),
        expected: aiRetrievalExpectations(
            hints: ["ai", "embedding", "vector_search", "malformed", "fallback"],
            warnings: ["malformed_payload"],
            fallback: "Show raw fallback and omit embedding/vector summary when vector payload parsing fails."
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: issueTraceability([189, 193])
    )

    static let evmJSONRPCContractSmoke = ProtocolFixture(
        id: "foundation.evm-json-rpc.contract-smoke",
        title: "EVM JSON-RPC request with synthetic method summary",
        family: .web3RPC,
        scenarioTags: ["web3", "evm", "json-rpc", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://rpc.example.com/evm",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"""
                    {"jsonrpc":"2.0","id":"fixture-1","method":"eth_call","params":[{"to":"0xSyntheticContract","data":"0xsyntheticCallData"},"latest"]}
                    """#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://rpc.example.com/evm",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"jsonrpc":"2.0","id":"fixture-1","result":"0xsyntheticResult"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["web3", "json_rpc", "evm", "eth_call"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["params.data"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["jsonrpc", "method", "id"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["RPC", "EVM"],
                optionalColumns: ["rpc_method": "eth_call"],
                inspectorTabs: ["RPC", "JSON", "Raw"],
                warningStates: [],
                exportSummaryFields: ["rpc_method", "chain_hint", "redacted_fields"],
                mcpSummaryFields: ["rpc_method", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let evmGasReceiptAndSendRawContractSmoke = ProtocolFixture(
        id: "web3.evm.gas-receipt-sendraw-contract",
        title: "EVM gas estimate, receipt lookup, and raw transaction-like payload",
        family: .web3RPC,
        scenarioTags: ["web3", "evm", "json-rpc", "estimate-gas", "receipt", "signed-payload", "issue-190"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            evmExchange(
                body: #"""
                {"jsonrpc":"2.0","id":"gas-1","method":"eth_estimateGas","params":[{"to":"0xSyntheticContract","data":"0xsyntheticCallData"}]}
                """#,
                response: #"{"jsonrpc":"2.0","id":"gas-1","result":"0x5208"}"#
            ),
            evmExchange(
                body: #"{"jsonrpc":"2.0","id":"receipt-1","method":"eth_getTransactionReceipt","params":["0xsyntheticTransactionHash"]}"#,
                response: #"{"jsonrpc":"2.0","id":"receipt-1","result":{"status":"0x1","transactionHash":"0xsyntheticTransactionHash"}}"#
            ),
            evmExchange(
                body: #"{"jsonrpc":"2.0","id":"send-1","method":"eth_sendRawTransaction","params":["synthetic-signed-transaction-payload"]}"#,
                response: #"{"jsonrpc":"2.0","id":"send-1","result":"0xsyntheticBroadcastHash"}"#
            ),
        ]),
        expected: web3Expectations(
            badges: ["RPC", "EVM"],
            hints: [
                "web3",
                "json_rpc",
                "evm",
                "eth_estimateGas",
                "eth_getTransactionReceipt",
                "eth_sendRawTransaction",
            ],
            redaction: ["params.data", "params.raw_transaction"],
            warnings: ["signed_payload_redaction_candidate"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([190])
    )

    static let evmBatchErrorAndLargeContractSmoke = ProtocolFixture(
        id: "web3.evm.batch-error-large-contract",
        title: "EVM JSON-RPC batch with mixed success, error, and bounded large sample",
        family: .web3RPC,
        scenarioTags: [
            "web3",
            "evm",
            "json-rpc",
            "batch",
            "error",
            "large",
            "high-volume",
            "issue-190",
            "issue-193",
        ],
        traffic: ProtocolFixtureTraffic(
            exchanges: [
                evmExchange(
                    body: evmBatchRequest(count: 24),
                    response: #"""
                    [
                      {"jsonrpc":"2.0","id":"batch-0","result":"0x1"},
                      {"jsonrpc":"2.0","id":"batch-1","error":{"code":-32000,"message":"synthetic execution error"}}
                    ]
                    """#
                ),
            ],
            estimatedPayloadBytes: 9_000
        ),
        expected: web3Expectations(
            badges: ["RPC", "Batch"],
            hints: ["web3", "json_rpc", "evm", "batch", "provider_error", "bounded_large"],
            redaction: ["params.data"],
            warnings: ["large_payload", "rpc_error"],
            fallback: "Keep request-list parsing bounded and summarize batch count without expanding every item."
        ),
        safetyClass: .large,
        sizeClass: .boundedStress,
        traceability: issueTraceability([190, 193])
    )

    static let evmMalformedJSONRPCContractSmoke = ProtocolFixture(
        id: "web3.evm.malformed-json-rpc-contract",
        title: "Malformed EVM JSON-RPC payload with safe fallback",
        family: .web3RPC,
        scenarioTags: ["web3", "evm", "json-rpc", "malformed", "fallback", "issue-190"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            evmExchange(
                body: #"{"jsonrpc":"2.0","id":"bad","method":"eth_call","params":["#,
                response: #"{"jsonrpc":"2.0","id":"bad","error":{"code":-32700,"message":"synthetic parse error"}}"#
            ),
        ]),
        expected: web3Expectations(
            badges: ["RPC", "Malformed"],
            hints: ["web3", "json_rpc", "evm", "malformed", "fallback"],
            redaction: ["params"],
            warnings: ["malformed_payload"],
            fallback: "Show raw fallback without classifying a method when JSON-RPC parsing fails."
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: issueTraceability([190, 193])
    )

    static let solanaHTTPRPCContractSmoke = ProtocolFixture(
        id: "web3.solana.http-rpc-contract",
        title: "Solana HTTP JSON-RPC request and response",
        family: .web3RPC,
        scenarioTags: ["web3", "solana", "json-rpc", "http-rpc", "issue-191"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://solana.example.com",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"""
                    {"jsonrpc":"2.0","id":"solana-1","method":"getLatestBlockhash","params":[{"commitment":"confirmed"}]}
                    """#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://solana.example.com",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"""
                    {"jsonrpc":"2.0","id":"solana-1","result":{"value":{"blockhash":"synthetic-blockhash","lastValidBlockHeight":123}}}
                    """#
                )
            )
        ]),
        expected: web3Expectations(
            badges: ["RPC", "Solana"],
            hints: ["web3", "json_rpc", "solana", "getLatestBlockhash"],
            redaction: [],
            warnings: [],
            fallback: nil
        ),
        safetyClass: .ordinary,
        sizeClass: .small,
        traceability: issueTraceability([191])
    )

    static let solanaWebSocketSubscriptionContractSmoke = ProtocolFixture(
        id: "web3.solana.websocket-subscription-contract",
        title: "Solana WebSocket subscription lifecycle",
        family: .web3RPC,
        scenarioTags: [
            "web3",
            "solana",
            "websocket-rpc",
            "subscription",
            "notification",
            "unsubscribe",
            "issue-191",
        ],
        traffic: ProtocolFixtureTraffic(
            webSocketMessages: [
                .init(
                    direction: .clientToServer,
                    url: "wss://solana.example.com",
                    body: #"""
                    {"jsonrpc":"2.0","id":1,"method":"logsSubscribe","params":[{"mentions":["SyntheticAccount111"]}]}
                    """#
                ),
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: #"{"jsonrpc":"2.0","id":1,"result":42}"#
                ),
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: #"""
                    {
                      "jsonrpc": "2.0",
                      "method": "logsNotification",
                      "params": {
                        "subscription": 42,
                        "result": {
                          "value": {
                            "signature": "synthetic-signature",
                            "logs": ["Program log: synthetic"]
                          }
                        }
                      }
                    }
                    """#
                ),
                .init(
                    direction: .clientToServer,
                    url: "wss://solana.example.com",
                    body: #"{"jsonrpc":"2.0","id":2,"method":"logsUnsubscribe","params":[42]}"#
                ),
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: #"{"jsonrpc":"2.0","id":2,"result":true}"#
                ),
            ]
        ),
        expected: web3Expectations(
            badges: ["RPC", "Solana", "WS"],
            hints: ["web3", "json_rpc", "solana", "subscription", "notification", "unsubscribe"],
            redaction: ["params.mentions", "signature"],
            warnings: ["subscription_lifecycle"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([191])
    )

    static let solanaLongAndMalformedSubscriptionContractSmoke = ProtocolFixture(
        id: "web3.solana.long-malformed-subscription",
        title: "Solana long subscription sample with malformed notification",
        family: .web3RPC,
        scenarioTags: [
            "web3",
            "solana",
            "websocket-rpc",
            "subscription",
            "malformed",
            "long-session",
            "issue-191",
            "issue-193",
        ],
        traffic: ProtocolFixtureTraffic(
            webSocketMessages: [
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: solanaNotificationSample(count: 16)
                ),
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: #"{"jsonrpc":"2.0","method":"logsNotification","params":"#
                ),
                .init(
                    direction: .serverToClient,
                    url: "wss://solana.example.com",
                    body: #"{"jsonrpc":"2.0","method":"logsNotification","error":{"code":-32000,"message":"synthetic subscription error"}}"#
                ),
            ],
            estimatedPayloadBytes: 6_000
        ),
        expected: web3Expectations(
            badges: ["RPC", "Solana", "WS"],
            hints: ["web3", "json_rpc", "solana", "subscription", "malformed", "fallback"],
            redaction: ["signature"],
            warnings: ["malformed_payload", "large_payload"],
            fallback: "Summarize bounded notification count and show raw fallback for malformed subscription messages."
        ),
        safetyClass: .malformed,
        sizeClass: .boundedStress,
        traceability: issueTraceability([191, 193])
    )

    static let x402ContractSmoke = ProtocolFixture(
        id: "foundation.x402.contract-smoke",
        title: "x402-style payment-required retry flow",
        family: .x402,
        scenarioTags: ["x402", "payment-required", "retry", "success", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/report",
                    headers: [.init(name: "Accept", value: "application/json")]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/report",
                    statusCode: 402,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"x402Version":1,"paymentRequired":true,"challenge":"synthetic-payment-challenge"}"#
                )
            ),
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/report",
                    headers: [
                        .init(name: "Accept", value: "application/json"),
                        .init(name: "X-Payment", value: "synthetic-payment-proof"),
                    ]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/report",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"ok":true,"receipt":"synthetic-receipt"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["x402", "payment_required", "retry_flow"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["X-Payment", "challenge", "receipt"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["x402Version", "paymentRequired", "ok"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["x402", "402"],
                optionalColumns: ["payment_flow": "required_then_success"],
                inspectorTabs: ["Payment", "Headers", "Raw"],
                warningStates: ["payment_metadata_redaction_candidate"],
                exportSummaryFields: ["payment_required", "retry_count", "redacted_fields"],
                mcpSummaryFields: ["payment_flow", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let x402MalformedAndMissingProofContractSmoke = ProtocolFixture(
        id: "x402.malformed-missing-proof-contract",
        title: "x402 malformed challenge and missing payment proof",
        family: .x402,
        scenarioTags: ["x402", "payment-required", "malformed", "missing-proof", "fallback", "issue-192"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/malformed",
                    headers: [.init(name: "Accept", value: "application/json")]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/malformed",
                    statusCode: 402,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"x402Version":1,"paymentRequired":true,"challenge":"#
                )
            ),
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/malformed",
                    headers: [.init(name: "Accept", value: "application/json")]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/malformed",
                    statusCode: 402,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"x402Version":1,"paymentRequired":true,"error":"missing synthetic payment proof"}"#
                )
            )
        ]),
        expected: x402Expectations(
            hints: ["x402", "payment_required", "malformed", "missing_proof", "fallback"],
            warnings: ["payment_metadata_redaction_candidate", "malformed_payload"],
            fallback: "Show payment-required state and raw fallback when the challenge is malformed or proof is missing."
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: issueTraceability([192, 193])
    )

    static let x402ProviderErrorMetadataContractSmoke = ProtocolFixture(
        id: "x402.provider-error-sensitive-metadata",
        title: "x402 provider error with synthetic payment metadata",
        family: .x402,
        scenarioTags: ["x402", "provider-error", "payment-metadata", "sensitive-metadata", "issue-192"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/report",
                    headers: [
                        .init(name: "Authorization", value: "Bearer synthetic-payment-token"),
                        .init(name: "X-Payment", value: "synthetic-payment-proof"),
                    ]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/report",
                    statusCode: 402,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"""
                    {"error":"synthetic provider rejected payment","paymentMetadata":{"network":"synthetic-chain","account":"synthetic-account","receipt":"synthetic-receipt"}}
                    """#
                )
            )
        ]),
        expected: x402Expectations(
            hints: ["x402", "payment_required", "provider_error", "payment_metadata"],
            warnings: ["payment_metadata_redaction_candidate", "export_destination_warning"],
            fallback: nil
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: issueTraceability([192])
    )

    static let malformedPayloadContractSmoke = ProtocolFixture(
        id: "foundation.malformed-json.contract-smoke",
        title: "Malformed JSON payload with bounded fallback contract",
        family: .unknown,
        scenarioTags: ["malformed", "json", "fallback", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://test.invalid/malformed",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"message":"unterminated""#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://test.invalid/malformed",
                    statusCode: 400,
                    headers: [.init(name: "Content-Type", value: "text/plain")],
                    body: "Malformed synthetic payload"
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["malformed", "fallback"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: [],
                redactedMarkers: [],
                safeFields: ["message"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["Malformed"],
                optionalColumns: ["parse_state": "failed"],
                inspectorTabs: ["Raw"],
                warningStates: ["malformed_payload"],
                exportSummaryFields: ["parse_state", "omitted_protocol_summary"],
                mcpSummaryFields: ["parse_state"],
                fallbackBehavior: "Show bounded raw fallback without protocol-specific inspector content."
            )
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let hostileOversizedDeepJSONContractSmoke = ProtocolFixture(
        id: "hostile.oversized-deep-json-contract",
        title: "Oversized and deeply nested JSON with bounded parser expectations",
        family: .unknown,
        scenarioTags: ["hostile", "oversized", "deep-nesting", "large", "fallback", "issue-193"],
        traffic: ProtocolFixtureTraffic(
            exchanges: [
                ProtocolFixtureExchange(
                    request: ProtocolFixtureMessage(
                        method: "POST",
                        url: "https://test.invalid/large-json",
                        headers: [.init(name: "Content-Type", value: "application/json")],
                        body: #"{"root":{"level1":{"level2":{"level3":{"level4":{"level5":{"secret":"synthetic-api-key","items":["# + repeatedItems(80) + #"]}}}}}}"#
                    ),
                    response: ProtocolFixtureMessage(
                        method: "HTTP",
                        url: "https://test.invalid/large-json",
                        statusCode: 200,
                        body: #"{"ok":true}"#
                    )
                ),
            ],
            estimatedPayloadBytes: 14_000
        ),
        expected: hostileExpectations(
            hints: ["hostile", "oversized", "deep_nesting", "fallback"],
            warnings: ["large_payload", "parser_budget"],
            fallback: "Avoid request-list expansion; inspector work should be bounded and cancellable."
        ),
        safetyClass: .large,
        sizeClass: .boundedStress,
        traceability: issueTraceability([193])
    )

    static let hostileLongStringTruncatedContractSmoke = ProtocolFixture(
        id: "hostile.long-string-truncated-contract",
        title: "Long string values and truncated response body",
        family: .unknown,
        scenarioTags: ["hostile", "long-string", "truncated", "fallback", "issue-193"],
        traffic: ProtocolFixtureTraffic(
            exchanges: [
                ProtocolFixtureExchange(
                    request: ProtocolFixtureMessage(
                        method: "POST",
                        url: "https://test.invalid/long-string",
                        headers: [.init(name: "Content-Type", value: "application/json")],
                        body: #"{"message":""# + repeatedScalar("synthetic-long-value-", count: 160) + #""}"#
                    ),
                    response: ProtocolFixtureMessage(
                        method: "HTTP",
                        url: "https://test.invalid/long-string",
                        statusCode: 206,
                        body: #"{"partial":"synthetic truncated response""#
                    )
                ),
            ],
            estimatedPayloadBytes: 8_000
        ),
        expected: hostileExpectations(
            hints: ["hostile", "long_string", "truncated", "fallback"],
            warnings: ["truncated_payload", "parser_budget"],
            fallback: "Show truncation state and keep export summaries explicit about omitted body content."
        ),
        safetyClass: .large,
        sizeClass: .boundedStress,
        traceability: issueTraceability([193])
    )

    static let hostilePartialSSEAndBytesContractSmoke = ProtocolFixture(
        id: "hostile.partial-sse-malformed-bytes",
        title: "Partial SSE stream and malformed byte-like payload",
        family: .ai,
        scenarioTags: ["hostile", "ai", "sse", "partial", "malformed-bytes", "fallback", "issue-193"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [.init(name: "Authorization", value: "Bearer synthetic-ai-token")],
                    body: #"{"model":"synthetic-model","input":"[SYNTHETIC_PROMPT]","stream":true}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")],
                    body: "synthetic-byte-prefix \\xF0\\x28\\x8C\\x28 replacement-marker"
                ),
                streamEvents: [
                    .init(event: "response.output_text.delta", data: #"{"delta":"partial synthetic text"}"#),
                    .init(event: nil, data: "data: [synthetic stream continues without completion]"),
                ]
            )
        ]),
        expected: aiStreamingExpectations(
            hints: ["ai", "streaming", "partial", "malformed_bytes", "fallback"],
            fallback: "Treat partial SSE and malformed byte-like payload as bounded raw fallback."
        ),
        safetyClass: .malformed,
        sizeClass: .medium,
        traceability: issueTraceability([188, 193])
    )

    static func issueTraceability(_ issues: Set<Int>) -> ProtocolFixtureTraceability {
        ProtocolFixtureTraceability(
            parentIssue: 176,
            childIssues: commonTraceability.childIssues.union(issues),
            futureIssues: commonTraceability.futureIssues
        )
    }

    static func aiStreamingExpectations(
        hints: Set<String>,
        fallback: String?
    ) -> ProtocolFixtureExpectations {
        ProtocolFixtureExpectations(
            metadataHints: hints,
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["Authorization", "X-API-Key", "input", "messages.content", "arguments", "partial_json"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["model", "status", "stop_reason"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["AI", "Stream"],
                optionalColumns: ["protocol": "AI", "streaming": "true"],
                inspectorTabs: ["AI", "Stream", "Tool Calls", "Raw"],
                warningStates: fallback == nil ? ["prompt_redaction_candidate"] : ["prompt_redaction_candidate", "malformed_payload"],
                exportSummaryFields: ["model", "stream_event_count", "tool_call_count", "redacted_fields"],
                mcpSummaryFields: ["model", "status", "streaming", "redacted"],
                fallbackBehavior: fallback
            )
        )
    }

    static func aiRetrievalExpectations(
        hints: Set<String>,
        warnings: [String],
        fallback: String?
    ) -> ProtocolFixtureExpectations {
        ProtocolFixtureExpectations(
            metadataHints: hints,
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["Authorization", "input", "retrieved_context", "messages.content", "query_embedding"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["model", "usage.total_tokens", "matches.score"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["AI", "RAG"],
                optionalColumns: ["protocol": "AI", "retrieval": "true"],
                inspectorTabs: ["AI", "Retrieval", "JSON", "Raw"],
                warningStates: warnings,
                exportSummaryFields: ["model", "retrieval_step_count", "redacted_fields"],
                mcpSummaryFields: ["model", "retrieval", "redacted"],
                fallbackBehavior: fallback
            )
        )
    }

    static func web3Expectations(
        badges: [String],
        hints: Set<String>,
        redaction: Set<String>,
        warnings: [String],
        fallback: String?
    ) -> ProtocolFixtureExpectations {
        ProtocolFixtureExpectations(
            metadataHints: hints,
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: redaction.union(["Authorization", "provider_api_key"]),
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["jsonrpc", "method", "id", "status"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: badges,
                optionalColumns: ["rpc": "true", "family": "web3"],
                inspectorTabs: ["RPC", "JSON", "Raw"],
                warningStates: warnings,
                exportSummaryFields: ["rpc_method", "batch_count", "chain_hint", "redacted_fields"],
                mcpSummaryFields: ["rpc_method", "status", "redacted"],
                fallbackBehavior: fallback
            )
        )
    }

    static func x402Expectations(
        hints: Set<String>,
        warnings: [String],
        fallback: String?
    ) -> ProtocolFixtureExpectations {
        ProtocolFixtureExpectations(
            metadataHints: hints,
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["Authorization", "X-Payment", "challenge", "receipt", "paymentMetadata"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["x402Version", "paymentRequired", "ok", "error"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["x402", "402"],
                optionalColumns: ["payment_flow": "true"],
                inspectorTabs: ["Payment", "Headers", "Raw"],
                warningStates: warnings,
                exportSummaryFields: ["payment_required", "retry_count", "provider_error", "redacted_fields"],
                mcpSummaryFields: ["payment_flow", "status", "redacted"],
                fallbackBehavior: fallback
            )
        )
    }

    static func hostileExpectations(
        hints: Set<String>,
        warnings: [String],
        fallback: String
    ) -> ProtocolFixtureExpectations {
        ProtocolFixtureExpectations(
            metadataHints: hints,
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["secret", "api_key", "Authorization"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["parse_state", "truncated", "omitted_protocol_summary"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["Bounded"],
                optionalColumns: ["parse_state": "bounded"],
                inspectorTabs: ["Raw"],
                warningStates: warnings,
                exportSummaryFields: ["parse_state", "truncation_state", "omitted_body_bytes"],
                mcpSummaryFields: ["parse_state", "redacted"],
                fallbackBehavior: fallback
            )
        )
    }

    static func evmExchange(body: String, response: String) -> ProtocolFixtureExchange {
        ProtocolFixtureExchange(
            request: ProtocolFixtureMessage(
                method: "POST",
                url: "https://rpc.example.com/evm",
                headers: [.init(name: "Content-Type", value: "application/json")],
                body: body
            ),
            response: ProtocolFixtureMessage(
                method: "HTTP",
                url: "https://rpc.example.com/evm",
                statusCode: 200,
                headers: [.init(name: "Content-Type", value: "application/json")],
                body: response
            )
        )
    }

    static func evmBatchRequest(count: Int) -> String {
        let calls = (0 ..< count).map { index in
            #"{"jsonrpc":"2.0","id":"batch-\#(index)","method":"eth_call","params":[{"to":"0xSyntheticContract","data":"0xsyntheticCallData"},"latest"]}"#
        }
        return "[\(calls.joined(separator: ","))]"
    }

    static func solanaNotificationSample(count: Int) -> String {
        let logs = (0 ..< count).map { index in
            #"{"signature":"synthetic-signature-\#(index)","logs":["Program log: synthetic-\#(index)"]}"#
        }.joined(separator: ",")
        return #"{"jsonrpc":"2.0","method":"logsNotification","params":{"subscription":42,"result":{"items":[\#(logs)]}}}"#
    }

    static func repeatedItems(_ count: Int) -> String {
        (0 ..< count).map { #""synthetic-item-\#($0)""# }.joined(separator: ",")
    }

    static func repeatedScalar(_ value: String, count: Int) -> String {
        Array(repeating: value, count: count).joined()
    }
}
