import AppKit
import Foundation

/// One file result: the URL plus the two strings the row shows.
struct FileHit: Identifiable, Hashable {
    let url: URL
    let name: String
    /// Containing folder, home-abbreviated ("~/Documents/Goorgle").
    let folder: String

    var id: URL { url }
}

/// Spotlight-backed file search, used by the `/file` mode in SearchBarView.
///
/// `NSMetadataQuery` is the same index Spotlight itself queries, so results
/// match what ⌘Space would find without Goorgle needing to walk the disk or
/// hold an index of its own. It must live on the main thread with a live run
/// loop, which the MainActor isolation here guarantees.
///
/// Note this only works because the app is *not* sandboxed: a sandboxed build
/// gets Spotlight results back fine, but `NSWorkspace.open` then refuses every
/// path outside its own container, so every result would be a dead end.
@MainActor
final class FileSearchClient {
    static let shared = FileSearchClient()

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<[FileHit], Never>?
    /// Identifies the in-flight search so a late cancellation can't take out
    /// the search that replaced it — see `cancel(generation:)`.
    private var generation = 0

    /// Matches that are technically correct but never what someone searching
    /// from a launcher meant: support files, caches, build output, and the
    /// insides of application bundles. Everything under Library goes — both
    /// `/Library` and `~/Library` — since a launcher search for "setup" was
    /// otherwise half XPC services and MIB data.
    private static let noisyPathFragments = [
        "/Library/",
        "/.Trash/",
        "/node_modules/",
        "/DerivedData/",
        ".app/Contents/",
        ".xcodeproj/",
        ".framework/",
    ]

    /// Top-level trees that belong to the OS rather than the user. `.app`
    /// bundles in /Applications are deliberately *not* excluded — finding an
    /// app by name and hitting Return to launch it is a feature, not noise.
    private static let systemPrefixes = [
        "/System/", "/private/", "/usr/", "/bin/", "/sbin/", "/opt/", "/Library/", "/cores/",
    ]

    func search(_ text: String, limit: Int = 6) async -> [FileHit] {
        cancel()
        generation += 1
        let generation = generation

        // Spotlight's LIKE treats * and ? as wildcards; stripping them keeps a
        // literal "report?.pdf" from matching half the disk.
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
        guard cleaned.count >= 2 else { return [] }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[FileHit], Never>) in
                self.continuation = continuation

                let query = NSMetadataQuery()
                query.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
                query.predicate = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(cleaned)*")
                query.notificationBatchingInterval = 0.1
                self.query = query

                self.observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: query,
                    queue: .main
                ) { _ in
                    // Reaches the query back through `self` rather than
                    // capturing it: NSMetadataQuery isn't Sendable, and the
                    // observer block is. Both ends are main-thread-only —
                    // the queue above and this actor's isolation.
                    MainActor.assumeIsolated {
                        guard let running = self.query else { return }
                        self.finish(with: Self.hits(from: running, limit: limit))
                    }
                }

                query.start()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(generation: generation) }
        }
    }

    /// Ranks by recency — most recently used, then most recently changed —
    /// which for a launcher beats Spotlight's own relevance ordering: the file
    /// you touched this morning is nearly always the one you're reaching for.
    private static func hits(from query: NSMetadataQuery, limit: Int) -> [FileHit] {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var scored: [(hit: FileHit, date: Date)] = []
        // Enough candidates to rank meaningfully without walking a 100k-result
        // set for a two-letter query.
        for index in 0..<min(query.resultCount, 500) {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            guard !Self.isNoise(path) else { continue }

            let url = URL(fileURLWithPath: path)
            let used = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
            let changed = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                ?? url.lastPathComponent

            scored.append((
                FileHit(url: url, name: name, folder: Self.abbreviatedFolder(for: url)),
                used ?? changed ?? .distantPast
            ))
        }

        return scored
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.hit)
    }

    private static func isNoise(_ path: String) -> Bool {
        if URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".") { return true }
        if systemPrefixes.contains(where: path.hasPrefix) { return true }
        return noisyPathFragments.contains { path.contains($0) }
    }

    private static func abbreviatedFolder(for url: URL) -> String {
        let folder = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    /// Ends the in-flight search, if any, resuming its caller with no results.
    /// Every exit path funnels through here so the continuation is resumed
    /// exactly once — resuming twice would trap.
    ///
    /// `generation` scopes the cancellation to one specific search. The task
    /// cancellation handler has to hop to the main actor, and by the time it
    /// lands the next keystroke's search may already be running: an unscoped
    /// cancel would kill *that* one, so typing steadily produced sporadic
    /// empty result lists.
    private func cancel(generation: Int? = nil) {
        if let generation, generation != self.generation { return }
        finish(with: [])
    }

    private func finish(with hits: [FileHit]) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        query?.stop()
        query = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: hits)
    }
}
