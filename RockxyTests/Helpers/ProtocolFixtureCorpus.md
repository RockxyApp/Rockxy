# Protocol Fixture Corpus

The protocol fixture corpus is Rockxy's test-only source of truth for future
protocol-aware debugging work. It is intentionally synthetic, offline, and
public-safe.

## Purpose

Use this corpus to test protocol metadata, redaction, inspector routing, export
summaries, MCP-safe summaries, session compatibility, and parser safety without
depending on ad hoc captures.

The umbrella tracker is RockxyApp/Rockxy#176.

## Fixture Contract

Every fixture should declare:

- a stable `id`
- a `family`
- scenario tags
- request/response or stream payload shape
- expected metadata hints
- redaction expectations
- UX contract expectations
- safety class
- size class
- issue traceability

UX contract fields describe expected future behavior. They do not mean the UI is
already implemented.

## Safety Rules

Fixtures must be synthetic or sanitized.

Do not add:

- real captured traffic
- real API keys or bearer tokens
- private keys
- seed phrases
- production payment proofs
- personal data
- local filesystem paths
- production provider URLs

Prefer `example.com`, `test.invalid`, and obvious synthetic placeholders such as
`synthetic-api-key`.

## Roadmap Mapping

The corpus supports:

- #143 protocol metadata architecture
- #144 privacy classification
- #145 redacted debugging-session bundles
- #146 export preview
- #177 parser safety budgets
- #178 session and HAR compatibility
- #179 inspector tab routing
- #180 large-session performance tests

Group A foundation work is tracked by:

- #186 schema, loader, and validation harness
- #187 UX contract expectations
- #188 AI streaming and tool-call fixtures
- #189 AI embeddings, RAG, and retrieval fixtures
- #190 EVM JSON-RPC fixtures
- #191 Solana RPC and subscription fixtures
- #192 x402 payment-flow fixtures
- #193 hostile, malformed, and large-payload fixtures
- #194 public-safety gates
- #195 fixture-to-feature traceability

## Extension Process

When adding a fixture:

1. Choose the smallest synthetic payload that represents the protocol shape.
2. Add scenario tags that map to the relevant issue and protocol behavior.
3. Declare expected metadata hints, redaction fields, UX contract fields, safety
   class, size class, and traceability.
4. Use `webSocketMessages` for subscription or bidirectional message flows.
5. Set `estimatedPayloadBytes` for bounded stress fixtures.
6. Add or update tests that prove the new issue coverage and safety behavior.

UX contract fields are planning contracts for future app behavior. They should
not be described as shipped UI unless the production view code implements them.
