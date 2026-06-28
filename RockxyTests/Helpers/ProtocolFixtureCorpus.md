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
- #194 public-safety gates
- #195 fixture-to-feature traceability
