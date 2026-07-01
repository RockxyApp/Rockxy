# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Previous release | Security fixes only |
| Older releases | No |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

If you discover a security vulnerability in Rockxy, please report it responsibly through one of these channels:

1. **GitHub Security Advisories** (preferred): Go to the [Security tab](https://github.com/RockxyApp/Rockxy/security/advisories) and click "Report a vulnerability."
2. **Email**: Send details to [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com) with the subject line "Rockxy Security Report".

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Suggested fix (if any)

### What to expect

- **Acknowledgment** within 48 hours of your report
- **Assessment** within 7 days, including severity classification
- **Fix timeline** communicated after assessment — critical issues are prioritized for the next patch release
- **Credit** in the release notes and CHANGELOG unless you prefer to remain anonymous

## Scope

The following are in scope for security reports:

- **XPC helper privilege escalation** — unauthorized callers invoking privileged operations
- **Certificate trust issues** — root CA mismanagement, stale certificate cleanup, trust state inconsistencies
- **Path traversal** — Map Local directory serving escaping the configured root
- **Plugin sandbox escape** — JavaScript plugins accessing filesystem, network, or system APIs beyond the bridge
- **Request injection** — breakpoint-edited requests causing unexpected behavior in the proxy pipeline
- **Sensitive data exposure** — stored sessions, exported files, or logs leaking credentials or tokens unintentionally

The following are out of scope:

- Traffic interception behavior that is the intended purpose of the tool (HTTPS MITM when root CA is trusted)
- Vulnerabilities in third-party dependencies — report these upstream and notify us so we can track the fix
- Social engineering or phishing attacks targeting users

## Security Architecture

Rockxy's security model is documented in the [README](README.md#security-architecture). Key boundaries:

- **App to helper**: XPC connection with code-signing requirements and certificate-chain validation
- **TLS interception**: Per-host certificate generation from a user-installed root CA
- **Plugin execution**: JavaScriptCore sandbox with timeout enforcement and no direct system access
- **Stored traffic**: SQLite + disk persistence with explicit save/export flows

## Disclosure Policy

We follow coordinated disclosure. We ask that you:

- Allow reasonable time for a fix before public disclosure
- Do not access or modify other users' data during testing
- Do not perform denial-of-service testing against production systems

We commit to:

- Not pursuing legal action against researchers acting in good faith
- Crediting reporters in security advisories and release notes
- Publishing fixes with clear CVE references when applicable
