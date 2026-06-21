import Foundation

/// Detects clips that look like a secret (API key, token, private key, secret env
/// assignment) so the UI can MASK them in the list — Mimer still stores and pastes the
/// full value (it's a local, no-cloud history and developers re-paste secrets on purpose).
///
/// Conservative + high-precision: we'd rather miss an exotic secret than mask ordinary
/// clips. A false positive is cheap anyway — the clip is still stored and pasteable, just
/// shown masked — but needless masking is annoying, so the rules favor known shapes.
enum SecretDetector {
    static func isSecret(_ text: String) -> Bool { kind(of: text) != nil }

    /// A short human label for the detected secret kind (used in the masked display), or nil.
    static func kind(of text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        // PEM private-key block (multi-line; the one secret shape with whitespace).
        if t.contains("-----BEGIN") && t.contains("PRIVATE KEY-----") { return "Private key" }

        // Secret-looking env assignment, e.g. `export AWS_SECRET_ACCESS_KEY=…` or `API_TOKEN="…"`.
        if let label = envAssignmentLabel(t) { return label }

        // Prefixed single-token credentials. Only consider the input if it's a lone token
        // (no whitespace) so prose containing a word like "secret" never matches.
        guard !t.contains(where: \.isWhitespace) else { return nil }

        if t.range(of: #"^(AKIA|ASIA)[A-Z0-9]{16}$"#, options: .regularExpression) != nil { return "AWS key" }
        for rule in prefixRules where t.hasPrefix(rule.prefix) && t.count >= rule.minLength { return rule.label }
        return nil
    }

    /// A masked, still-identifiable display string for a secret clip (label + last 4),
    /// or nil if `text` isn't a secret. The real value is never altered — only the display.
    static func maskedPreview(_ text: String) -> String? {
        guard let label = kind(of: text) else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Last-4 hint only for single-token secrets; multi-line (PEM) / spaced blobs show the bare label.
        guard !t.contains(where: \.isWhitespace), t.count >= 8 else { return "\(label) ••••" }
        return "\(label) ••••\(t.suffix(4))"
    }

    // MARK: - Rules

    private struct PrefixRule { let prefix: String; let minLength: Int; let label: String }

    private static let prefixRules: [PrefixRule] = [
        PrefixRule(prefix: "sk-", minLength: 20, label: "API key"),          // OpenAI & others
        PrefixRule(prefix: "sk_live_", minLength: 20, label: "Stripe key"),
        PrefixRule(prefix: "sk_test_", minLength: 20, label: "Stripe key"),
        PrefixRule(prefix: "rk_live_", minLength: 20, label: "Stripe key"),
        PrefixRule(prefix: "ghp_", minLength: 36, label: "GitHub token"),
        PrefixRule(prefix: "gho_", minLength: 36, label: "GitHub token"),
        PrefixRule(prefix: "ghs_", minLength: 36, label: "GitHub token"),
        PrefixRule(prefix: "ghu_", minLength: 36, label: "GitHub token"),
        PrefixRule(prefix: "github_pat_", minLength: 30, label: "GitHub token"),
        PrefixRule(prefix: "glpat-", minLength: 20, label: "GitLab token"),
        PrefixRule(prefix: "xoxb-", minLength: 20, label: "Slack token"),
        PrefixRule(prefix: "xoxp-", minLength: 20, label: "Slack token"),
        PrefixRule(prefix: "xoxa-", minLength: 20, label: "Slack token"),
        PrefixRule(prefix: "AIza", minLength: 39, label: "Google API key"),
        PrefixRule(prefix: "ya29.", minLength: 20, label: "OAuth token")
    ]

    /// `NAME=value` (optionally `export `-prefixed) where NAME has a secret-word
    /// *component* (underscore-bounded) and the value is non-trivial. Case-insensitive,
    /// so `api_key=…` and `PASSWORD=…` match while `monkey=…` / `PORT=…` don't.
    private static func envAssignmentLabel(_ t: String) -> String? {
        // Single line only — don't match multi-line blobs.
        guard !t.contains("\n") else { return nil }
        let pattern = #"^(export\s+)?([A-Za-z0-9]+_)*(key|token|secret|password|passwd|pwd|apikey)(_[A-Za-z0-9]+)*\s*=\s*['"]?\S{6,}"#
        return t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil ? "Secret" : nil
    }
}
