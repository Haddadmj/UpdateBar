import Foundation

/// A single package/app that has an update available from some source.
struct OutdatedItem: Identifiable, Hashable, Sendable {
    /// Stable identifier used for upgrade commands (package name or store id).
    let identifier: String
    let name: String
    let currentVersion: String?
    let latestVersion: String?

    var id: String { identifier }

    var versionSummary: String {
        switch (currentVersion, latestVersion) {
        case let (cur?, new?): return "\(cur) → \(new)"
        case let (_, new?): return "→ \(new)"
        case let (cur?, _): return cur
        default: return ""
        }
    }
}

/// The live state of one update source, as rendered in the UI.
struct SourceState: Identifiable, Sendable {
    enum Status: Sendable, Equatable {
        case idle
        case checking
        case upgrading
        case ok
        case failed(String)
    }

    let id: String
    let displayName: String
    let iconSystemName: String
    let requiresAdmin: Bool
    var status: Status = .idle
    var items: [OutdatedItem] = []
    var lastChecked: Date?
    /// Non-nil when the source is present but intentionally not managed (e.g. Apple's
    /// system Ruby). Shown as an informational, non-actionable row.
    var note: String?

    var count: Int { items.count }
    var isManageable: Bool { note == nil }
}
