import Foundation

/// One thing the session checker noticed.
///
/// A problem means the folder should not be relied on as it is. A warning is worth a look but does
/// not stop the folder being used.
public struct CheckFinding: Equatable, Sendable {
    public enum Severity: Sendable {
        case problem, warning
    }

    public let severity: Severity
    /// What it is about: a path inside the folder, `session.json`, or `folder`.
    public let subject: String
    /// A plain sentence fragment that reads on after the subject.
    public let message: String

    public init(_ severity: Severity, _ subject: String, _ message: String) {
        self.severity = severity
        self.subject = subject
        self.message = message
    }
}
