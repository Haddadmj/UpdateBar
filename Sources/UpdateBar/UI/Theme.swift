import SwiftUI

/// The spacing scale. Every gap and inset in the UI comes from here, so that a group
/// always reads as a group: more space around it than inside it.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

enum Radius {
    static let tile: CGFloat = 6
    static let row: CGFloat = 8
}

/// A source's symbol on a tinted square, shared by the menu and Settings so a source
/// looks like the same thing in both places.
struct SourceIconTile: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 24, height: 24)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.tile))
            .accessibilityHidden(true)
    }
}

/// Marks a source as belonging to macOS rather than the user, which is why it offers
/// no upgrades.
struct SystemBadge: View {
    var body: some View {
        Text("System")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.xs + 2)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .help("Part of macOS, so UpdateBar leaves it alone")
    }
}

/// The large line at the top of the menu.
///
/// Separate from the view because getting it wrong is a claim about the user's
/// machine: "All up to date" while a source is failing, or while the check that would
/// establish it is still running, is simply false.
enum MenuHeadline {
    static func text(total: Int, failed: Int, enabledSources: Int, isChecking: Bool) -> String {
        if enabledSources == 0 { return "No sources enabled" }
        if total > 0 { return total == 1 ? "1 update" : "\(total) updates" }
        if isChecking { return "Checking…" }
        return failed > 0 ? "No updates found" : "All up to date"
    }
}
