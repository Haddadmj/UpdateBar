import Foundation

/// Quoting for values that end up inside a generated shell command.
///
/// Package identifiers are parsed out of third-party CLI output and land in a
/// `.command` file that a terminal executes. Registry names are constrained
/// enough that nothing exploitable exists today — but that is a fact about
/// today's inputs, not a property of this code, and the whole class of problem
/// costs one function to remove.
enum ShellQuoting {
    /// Wraps in single quotes, escaping embedded ones as `'\''`. Inside single
    /// quotes the shell expands nothing, so this is safe for any content.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Identifiers as a space-separated, individually quoted argument list.
    static func arguments(_ values: [String]) -> String {
        values.map(singleQuoted).joined(separator: " ")
    }
}
