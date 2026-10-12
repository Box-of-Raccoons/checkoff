import AppKit
import CheckoffCore
import SwiftUI

/// Where the task file lives.
enum TasksFile {
    /// `defaults write com.boxofraccoons.checkoff tasksFile <path>` points the app at another file.
    static let defaultsKey = "tasksFile"

    static func resolveURL(defaults: UserDefaults = .standard) -> URL {
        if let custom = defaults.string(forKey: defaultsKey), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Checkoff/tasks.md")
    }

    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}

/// The task list as the window sees it. Every change goes through `change`,
/// which writes the file; edits made outside the app arrive through `reload`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document = TodoDocument()
    @Published private(set) var today = DateOnly(Date())
    @Published var errorMessage: String?
    /// Bumped by the New Task menu command; the window focuses the add field when it changes.
    @Published var focusAddField = 0

    let fileURL: URL
    private let store: TodoStore
    private var watcher: FileWatcher?
    private var observers: [NSObjectProtocol] = []

    init(fileURL: URL, watch: Bool = true) {
        self.fileURL = fileURL
        store = TodoStore(url: fileURL)
        reload()
        guard watch else { return }

        watcher = FileWatcher(file: fileURL) { [weak self] in
            self?.reload()
        }
        // Backstops for a missed file event, and for the date rolling over while the window is open.
        for name in [NSApplication.didBecomeActiveNotification, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
    }

    func reload() {
        do {
            if try store.reload() { document = store.document }
            errorMessage = nil
        } catch {
            errorMessage = "Could not read \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
        let now = DateOnly(Date())
        if now != today { today = now }
    }

    func change(_ body: (inout TodoDocument) -> Void) {
        do {
            try store.mutate(body)
            document = store.document
            errorMessage = nil
        } catch {
            errorMessage = "Could not save \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// Window state that is not part of the task file.
@MainActor
final class ListUI: ObservableObject {
    struct DropTarget: Equatable {
        /// The row under the pointer; nil for the space below the last task.
        var row: UUID?
        var action: DropAction
    }

    private static let collapsedKey = "collapsedTitles"

    var draggingID: UUID?
    @Published var dropTarget: DropTarget?
    @Published var editingID: UUID?
    @Published var addingSubTaskTo: UUID?
    @Published var duePickerFor: UUID?
    @Published var confirmCheck: TodoItem?
    @Published var confirmDelete: TodoItem?
    /// Titles of parents whose sub-tasks are folded away. Kept by title so it survives a restart.
    @Published private(set) var collapsed: Set<String>

    init() {
        collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? [])
    }

    func isCollapsed(_ item: TodoItem) -> Bool {
        collapsed.contains(item.title)
    }

    func setCollapsed(_ item: TodoItem, _ value: Bool, in document: TodoDocument) {
        var next = collapsed.intersection(document.items.map(\.title))  // forget tasks that are gone
        if value { next.insert(item.title) } else { next.remove(item.title) }
        collapsed = next
        UserDefaults.standard.set(Array(next).sorted(), forKey: Self.collapsedKey)
    }
}
