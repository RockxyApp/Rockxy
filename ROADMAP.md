# Rockxy Roadmap

Rockxy is an open-source native macOS debugging workflow platform for developers who need to inspect, understand, and shape network traffic with confidence.

This roadmap describes the public engineering direction for Rockxy. It is intentionally high-level, workflow-oriented, and not tied to fixed dates.

## Vision

Rockxy aims to be a thoughtful native macOS debugging tool for modern development workflows: fast capture, clear inspection, reliable HTTPS debugging, strong local privacy, and a desktop experience that feels at home on macOS.

The next public product direction is to make Rockxy an all-in-one local debugging app for modern networked software: API, mobile, AI, WebSocket, GraphQL, MCP-assisted workflows, and Web3/RPC traffic.

The project values native macOS craftsmanship, debugging workflow quality, reliability, transparent engineering, and sustainable open-source development.

## How This Roadmap Works

This roadmap shows areas of active and planned public work. It does not represent a delivery promise, release schedule, or business roadmap.

- **Current Focus**: work receiving active attention.
- **Planned**: accepted public direction without a committed date.
- **Exploring**: areas being researched or shaped through community feedback.

For day-to-day execution, see the [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1) GitHub Project.

## Current Focus

- Improve Developer Setup workflows for Flutter, iOS, Android, React Native, backend runtimes, CLI tools, and container-based development.
- Strengthen certificate and HTTPS debugging guidance, including clearer trust-state recovery and safer setup instructions.
- Improve capture reliability, request-list performance, filtering behavior, and inspector responsiveness during real debugging sessions.
- Expand regression coverage for core workflows: capture start/stop, session persistence, inspector rendering, filtering, replay, and setup validation.
- Improve public documentation so new users can move from install to first useful capture with less guesswork.
- Build the foundation for protocol-aware debugging across AI traffic, Web3/RPC flows, x402-style payment flows, and future protocol lenses while preserving Rockxy's local-first privacy model.

## Project Plan

The public project plan is to deliver protocol-aware debugging in clear, reviewable slices. Each slice should be useful on its own, preserve the existing Rockxy workflow, and avoid coupling future protocol support to one-off UI or parser logic.

| Slice | User outcome | Primary tracking |
|---|---|---|
| Protocol Foundation | Captured traffic can carry safe, typed protocol metadata without breaking sessions, HAR export, filters, replay, or large-capture performance. | [#143](https://github.com/RockxyApp/Rockxy/issues/143), [#144](https://github.com/RockxyApp/Rockxy/issues/144), [#176](https://github.com/RockxyApp/Rockxy/issues/176), [#177](https://github.com/RockxyApp/Rockxy/issues/177), [#178](https://github.com/RockxyApp/Rockxy/issues/178), [#179](https://github.com/RockxyApp/Rockxy/issues/179), [#180](https://github.com/RockxyApp/Rockxy/issues/180) |
| Redacted Evidence | Users can package the debugging facts needed for a repro while previewing what will leave their machine. | [#145](https://github.com/RockxyApp/Rockxy/issues/145), [#146](https://github.com/RockxyApp/Rockxy/issues/146), [#184](https://github.com/RockxyApp/Rockxy/issues/184) |
| AI Traffic Debugging | AI requests, streaming responses, tool-call chains, safety signals, and selected usage summaries become understandable inside the normal Rockxy inspector workflow. | [#147](https://github.com/RockxyApp/Rockxy/issues/147), [#148](https://github.com/RockxyApp/Rockxy/issues/148), [#149](https://github.com/RockxyApp/Rockxy/issues/149), [#150](https://github.com/RockxyApp/Rockxy/issues/150), [#151](https://github.com/RockxyApp/Rockxy/issues/151), [#152](https://github.com/RockxyApp/Rockxy/issues/152), [#156](https://github.com/RockxyApp/Rockxy/issues/156) |
| Local AI Trace Context | Optional local trace data can connect app-level AI workflow steps to the network traffic Rockxy captures. | [#153](https://github.com/RockxyApp/Rockxy/issues/153), [#154](https://github.com/RockxyApp/Rockxy/issues/154), [#155](https://github.com/RockxyApp/Rockxy/issues/155) |
| Web3/RPC Debugging | JSON-RPC, Solana RPC, wallet/provider-visible flows, x402-style payment traffic, replay helpers, and simulation handoff become inspectable as network evidence. | [#157](https://github.com/RockxyApp/Rockxy/issues/157), [#158](https://github.com/RockxyApp/Rockxy/issues/158), [#159](https://github.com/RockxyApp/Rockxy/issues/159), [#160](https://github.com/RockxyApp/Rockxy/issues/160), [#161](https://github.com/RockxyApp/Rockxy/issues/161), [#162](https://github.com/RockxyApp/Rockxy/issues/162), [#163](https://github.com/RockxyApp/Rockxy/issues/163), [#164](https://github.com/RockxyApp/Rockxy/issues/164), [#165](https://github.com/RockxyApp/Rockxy/issues/165), [#166](https://github.com/RockxyApp/Rockxy/issues/166) |
| Local Web3 Trace Context | Optional TypeScript trace labels can help connect browser/app Web3 actions to the captured RPC traffic. | [#167](https://github.com/RockxyApp/Rockxy/issues/167), [#168](https://github.com/RockxyApp/Rockxy/issues/168) |
| Workflow Integration | AI and Web3 metadata become useful in filters, badges, columns, rules, comparison, MCP summaries, and Developer Setup instead of living in isolated panels. | [#169](https://github.com/RockxyApp/Rockxy/issues/169), [#170](https://github.com/RockxyApp/Rockxy/issues/170), [#171](https://github.com/RockxyApp/Rockxy/issues/171), [#172](https://github.com/RockxyApp/Rockxy/issues/172), [#173](https://github.com/RockxyApp/Rockxy/issues/173), [#174](https://github.com/RockxyApp/Rockxy/issues/174), [#175](https://github.com/RockxyApp/Rockxy/issues/175) |
| Public Positioning And Docs | Public website and documentation explain only implemented, source-backed behavior while still making the long-term direction understandable. | [#181](https://github.com/RockxyApp/Rockxy/issues/181), [#182](https://github.com/RockxyApp/Rockxy/issues/182), [#183](https://github.com/RockxyApp/Rockxy/issues/183), [#184](https://github.com/RockxyApp/Rockxy/issues/184) |

## Delivery Path

This is the preferred delivery order for the current public roadmap. It is intentionally date-free. Each step should ship only when the underlying implementation, tests, privacy behavior, and documentation are ready.

### 1. Foundation: Protocol Metadata, Privacy, And Evidence

First, Rockxy needs the shared foundation that prevents each new protocol from becoming a one-off feature.

- Add protocol metadata architecture for modern traffic inspection: [#143](https://github.com/RockxyApp/Rockxy/issues/143)
- Add privacy classification for AI, Web3, and exported traffic: [#144](https://github.com/RockxyApp/Rockxy/issues/144)
- Extend redacted debugging-session bundles with protocol summaries: [#145](https://github.com/RockxyApp/Rockxy/issues/145)
- Add export preview for redacted debugging evidence: [#146](https://github.com/RockxyApp/Rockxy/issues/146)
- Add protocol fixture corpus for AI, Web3, and x402 traffic: [#176](https://github.com/RockxyApp/Rockxy/issues/176)
- Add parser safety budgets for protocol lenses: [#177](https://github.com/RockxyApp/Rockxy/issues/177)
- Preserve session and HAR compatibility while adding protocol metadata: [#178](https://github.com/RockxyApp/Rockxy/issues/178)
- Add regression and large-session coverage for protocol metadata: [#179](https://github.com/RockxyApp/Rockxy/issues/179), [#180](https://github.com/RockxyApp/Rockxy/issues/180)

### 2. AI Workflow Debugging

After the foundation is in place, Rockxy should make AI traffic understandable inside the normal capture, filter, select, inspect, replay, compare, and export workflow.

- Detect AI provider and model traffic in captured sessions: [#147](https://github.com/RockxyApp/Rockxy/issues/147)
- Add an AI inspector tab for selected model traffic: [#148](https://github.com/RockxyApp/Rockxy/issues/148)
- Add streaming diagnostics for AI responses: [#149](https://github.com/RockxyApp/Rockxy/issues/149)
- Reconstruct AI tool-call chains from captured traffic: [#150](https://github.com/RockxyApp/Rockxy/issues/150)
- Add AI security warnings for sensitive prompts and tool payloads: [#151](https://github.com/RockxyApp/Rockxy/issues/151)
- Add AI cost, usage, and reliability summaries for selected traffic: [#152](https://github.com/RockxyApp/Rockxy/issues/152)
- Correlate RAG and vector workflow traffic with model calls: [#156](https://github.com/RockxyApp/Rockxy/issues/156)
- Design and build optional local tracing support for Python AI workflows: [#153](https://github.com/RockxyApp/Rockxy/issues/153), [#154](https://github.com/RockxyApp/Rockxy/issues/154), [#155](https://github.com/RockxyApp/Rockxy/issues/155)

### 3. Web3, RPC, And Payment-Flow Debugging

Rockxy should then make blockchain-era traffic debuggable as network evidence, without becoming a wallet, block explorer, or smart-contract IDE.

- Detect Web3 JSON-RPC traffic in captured sessions: [#157](https://github.com/RockxyApp/Rockxy/issues/157)
- Add Web3/RPC inspector tab for selected traffic: [#158](https://github.com/RockxyApp/Rockxy/issues/158)
- Add Solana RPC inspection support: [#159](https://github.com/RockxyApp/Rockxy/issues/159)
- Detect wallet and provider interaction patterns where visible: [#160](https://github.com/RockxyApp/Rockxy/issues/160)
- Group Web3 actions into debuggable RPC flows: [#161](https://github.com/RockxyApp/Rockxy/issues/161)
- Add Web3 RPC error explanations: [#162](https://github.com/RockxyApp/Rockxy/issues/162)
- Add Web3 security warnings for risky network-visible behavior: [#163](https://github.com/RockxyApp/Rockxy/issues/163)
- Add x402 payment-flow detection and inspection: [#164](https://github.com/RockxyApp/Rockxy/issues/164)
- Add replay helpers and simulation handoff for selected JSON-RPC/Web3 traffic: [#165](https://github.com/RockxyApp/Rockxy/issues/165), [#166](https://github.com/RockxyApp/Rockxy/issues/166)
- Design and build optional TypeScript trace context for Web3 flow labels: [#167](https://github.com/RockxyApp/Rockxy/issues/167), [#168](https://github.com/RockxyApp/Rockxy/issues/168)

### 4. Cross-Workflow Integration

Once AI and Web3 metadata exists, the value should show up across Rockxy's existing surfaces rather than as separate dashboards.

- Add smart filters for AI and Web3 traffic: [#169](https://github.com/RockxyApp/Rockxy/issues/169)
- Add compact request-list badges and optional columns: [#170](https://github.com/RockxyApp/Rockxy/issues/170), [#171](https://github.com/RockxyApp/Rockxy/issues/171)
- Add protocol-aware rule predicates for AI and Web3 traffic: [#172](https://github.com/RockxyApp/Rockxy/issues/172)
- Compare successful and failed AI/Web3 workflows: [#173](https://github.com/RockxyApp/Rockxy/issues/173)
- Expose redacted AI/Web3 summaries through local MCP: [#174](https://github.com/RockxyApp/Rockxy/issues/174)
- Add Developer Setup presets for AI and Web3 debugging: [#175](https://github.com/RockxyApp/Rockxy/issues/175)

### 5. Public Website And Docs

Public copy and documentation should follow implementation. The website may explain the direction, but feature docs should claim only source-backed behavior.

- Update public website positioning for modern API, AI, mobile, and Web3 debugging: [#181](https://github.com/RockxyApp/Rockxy/issues/181)
- Add public docs for AI traffic inspection after implementation: [#182](https://github.com/RockxyApp/Rockxy/issues/182)
- Add public docs for Web3/RPC inspection after implementation: [#183](https://github.com/RockxyApp/Rockxy/issues/183)
- Add public docs for evidence bundles after implementation: [#184](https://github.com/RockxyApp/Rockxy/issues/184)

## Workflow Priorities

### Stability And Reliability

- More predictable proxy start/stop behavior.
- Safer recovery when macOS proxy settings, helper state, or certificate trust are out of sync.
- Better handling of large captures and long-running debugging sessions.
- More durable transaction persistence, session restore, HAR import/export, and workflow continuity.

### Native macOS UX

- Continued refinement of window, tab, toolbar, keyboard, and inspector behavior.
- Better support for workspace-oriented debugging flows.
- Clearer feedback when capture, trust, helper, or setup state needs attention.
- Accessibility and keyboard-flow improvements where they improve real debugging work.

### Debugging Workflow Improvements

- Better filtering, search, grouping, and request-list ergonomics.
- Stronger replay, diff, rules, breakpoint, and scripting workflows.
- Improved WebSocket and GraphQL inspection.
- Exploration of gRPC and Protocol Buffers debugging workflows.
- Continued research into HTTP/2 and HTTP/3 behavior.
- Protocol-aware inspection for AI traffic, Web3/RPC calls, and x402-style payment flows.
- Redacted evidence bundles that help users share reproducible debugging context safely.

### Developer Setup

- Safer Flutter HTTPS guidance.
- Improved setup paths for mobile simulators, emulators, and physical devices.
- Clearer runtime-specific examples for Node.js, Python, Go, Ruby, Java, Docker, API clients, and CLI tools.
- Better validation language so Rockxy reports what it can verify without overstating device or runtime attribution.
- Source-backed setup guidance for AI and Web3 debugging workflows as those features ship.

### Documentation And Community

- Better onboarding for first-time users and contributors.
- Clearer troubleshooting for certificates, helper installation, capture issues, and platform-specific setup.
- More contributor-friendly issues, labels, and project-board visibility.
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) for questions, ideas, workflow feedback, and community examples.

## Exploring

These areas are public research topics, not committed release promises:

- AI traffic inspection, streaming diagnostics, tool-call chain reconstruction, and optional local trace correlation.
- Web3/RPC inspection, wallet/provider-visible flow debugging, and x402-style payment-flow visibility.
- gRPC and Protocol Buffers inspection workflows.
- HTTP/2 and HTTP/3 support.
- More protocol fixtures and sample apps for testing.
- Improved scripting diagnostics and examples.
- Better local workflow integrations that preserve Rockxy's privacy and local-first model.
- Contributor tooling for easier build, test, lint, and fixture workflows.

## Out Of Scope For This Public Roadmap

This roadmap does not include:

- Monetization plans.
- Enterprise strategy.
- Future paid features.
- Private infrastructure direction.
- Business operations.
- Competitive strategy.
- Sensitive security implementation details before responsible disclosure.
- Internal planning that is not ready for public discussion.

## Contributor Expectations

Contributions are welcome when they improve public Rockxy workflows: code, tests, documentation, reproducible bug reports, setup notes, protocol examples, and UX feedback.

Good public roadmap issues should explain:

- the debugging workflow being improved,
- the user-visible problem,
- the expected behavior,
- likely affected areas,
- useful validation steps.

Large or ambiguous work should start as a discussion or design issue before implementation.

## Transparency Notes

Rockxy tries to be transparent about public engineering direction without turning the roadmap into a promise list. Priorities can change when reliability, security, platform behavior, or user reports reveal more important work.

When an item is exploratory, it should remain labeled as exploratory until the implementation shape is understood.
