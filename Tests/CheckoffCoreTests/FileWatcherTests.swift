import Foundation
import Testing
@testable import CheckoffCore

/// Counts callbacks from a watcher running on its own queue.
final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Waits up to two seconds for a callback beyond `seen`.
    func changed(since seen: Int) async -> Bool {
        for _ in 0..<200 {
            if value > seen { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

@Suite struct FileWatcherTests {
    let queue = DispatchQueue(label: "checkoff.tests.watcher")

    func watch(_ folder: TempFolder) -> (FileWatcher, ChangeCounter) {
        let counter = ChangeCounter()
        let watcher = FileWatcher(file: folder.file, queue: queue) { counter.bump() }
        return (watcher, counter)
    }

    @Test func noticesAFileSavedByReplacingIt() async throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let (watcher, counter) = watch(folder)
        try folder.write("- [x] Milk\n")  // atomic: a new file renamed over the old one
        #expect(await counter.changed(since: 0))
        withExtendedLifetime(watcher) {}
    }

    @Test func noticesAFileEditedInPlace() async throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let (watcher, counter) = watch(folder)
        let handle = try FileHandle(forWritingTo: folder.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] Bread\n".utf8))
        try handle.close()
        #expect(await counter.changed(since: 0))
        withExtendedLifetime(watcher) {}
    }

    @Test func noticesAFileThatDidNotExistYet() async throws {
        let folder = try TempFolder()
        let (watcher, counter) = watch(folder)
        try folder.write("- [ ] Milk\n")
        #expect(await counter.changed(since: 0))
        withExtendedLifetime(watcher) {}
    }

    @Test func keepsNoticingAfterTheFileIsReplaced() async throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let (watcher, counter) = watch(folder)
        try folder.write("- [x] Milk\n")
        #expect(await counter.changed(since: 0))
        try await Task.sleep(nanoseconds: 200_000_000)  // let the replace's own events settle

        // The file is a different one now; an in-place edit to it must still be seen.
        let seen = counter.value
        let handle = try FileHandle(forWritingTo: folder.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] Bread\n".utf8))
        try handle.close()
        #expect(await counter.changed(since: seen))
        withExtendedLifetime(watcher) {}
    }

    @Test func createsTheFolderItWatches() async throws {
        let folder = try TempFolder()
        let nested = folder.url.appendingPathComponent("new/tasks.md")
        let counter = ChangeCounter()
        let watcher = FileWatcher(file: nested, queue: queue) { counter.bump() }
        #expect(FileManager.default.fileExists(atPath: nested.deletingLastPathComponent().path))
        try "- [ ] Milk\n".write(to: nested, atomically: true, encoding: .utf8)
        #expect(await counter.changed(since: 0))
        withExtendedLifetime(watcher) {}
    }

    @Test func staysQuietWhenNothingChanges() async throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let (watcher, counter) = watch(folder)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(counter.value == 0)
        withExtendedLifetime(watcher) {}
    }
}
