import Foundation

/// Runs the full source pipeline once and prints a report, then exits.
/// Invoked via `UpdateBar --check`.
enum HeadlessCheck {
    static func runAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let runner = ProcessRunner()
            let all = SourceRegistry.allSources(runner: runner)
            print("UpdateBar self-check\n====================")
            var total = 0
            for source in all {
                let available = await source.isAvailable()
                guard available else {
                    print("• \(source.displayName): not installed — skipped")
                    continue
                }
                if let note = await source.managementNote() {
                    print("• \(source.displayName): not managed — \(note)")
                    continue
                }
                do {
                    let items = try await source.checkOutdated()
                    total += items.count
                    print("• \(source.displayName): \(items.count) update(s)")
                    for item in items.prefix(20) {
                        print("    - \(item.name)  \(item.versionSummary)")
                    }
                } catch {
                    print("• \(source.displayName): ERROR — \(error.localizedDescription)")
                }
            }
            print("--------------------\nTotal pending updates: \(total)")
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
