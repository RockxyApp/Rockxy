import Foundation

/// Applies deterministic capture semantics when a small model contradicts reviewed evidence.
///
/// The model still produces the response. Rockxy only replaces it when the wording conflicts
/// with a protocol fact that the local analyzer can prove from the approved capture.
struct AssistantResponseGrounder {
    func finalize(
        _ text: String,
        against result: InvestigationResult,
        userQuestion: String? = nil
    )
        -> String
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEstablishedConnect(result),
              contradictsEstablishedConnect(trimmed)
              || mentionsIrrelevantPayload(trimmed, userQuestion: userQuestion) else
        {
            return trimmed
        }

        let evidence = result.evidence
            .prefix(3)
            .map { "• \($0.title)" }
            .joined(separator: "\n")
        return """
        \(result.summary)

        What Rockxy captured:
        \(evidence)

        \(result.nextStep)
        """
    }

    private func isEstablishedConnect(_ result: InvestigationResult) -> Bool {
        let hasConnectSemantics = result.evidence.contains {
            $0.id.localizedCaseInsensitiveContains("protocol.connect")
        }
        let hasSuccessfulStatus = result.evidence.contains {
            $0.id.localizedCaseInsensitiveContains("response.status")
                && $0.title.range(
                    of: #"HTTP 2\d\d\b"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
        }
        return hasConnectSemantics && hasSuccessfulStatus
    }

    private func contradictsEstablishedConnect(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return [
            "failed connect request",
            "connect request failed",
            "connection was not established",
            "tunnel was not established",
            "cannot determine if the tunnel",
            "cannot determine whether the tunnel",
            "cannot confirm if the tunnel",
            "cannot confirm whether the tunnel",
        ].contains { normalized.contains($0) }
    }

    private func mentionsIrrelevantPayload(_ text: String, userQuestion: String?) -> Bool {
        let question = userQuestion?.lowercased() ?? ""
        let asksAboutPayload = [
            "body",
            "content",
            "payload",
            "request data",
            "response data",
        ].contains { question.contains($0) }
        guard !asksAboutPayload else { return false }

        let normalized = text.lowercased()
        let discussesBody = normalized.contains("payload")
            || normalized.contains("request body")
            || normalized.contains("response body")
        let describesAbsence = [
            "unavailable",
            "not available",
            "isn't available",
            "wasn't available",
            "missing",
            "empty",
            "omitted",
            "not captured",
            "wasn't captured",
            "without payload",
            "no payload",
            "no request body",
            "no response body",
        ].contains { normalized.contains($0) }
        return discussesBody && describesAbsence
    }
}
