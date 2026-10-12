import Foundation

/// Calls back when the task file changes on disk.
///
/// Watches the folder as well as the file: an editor that saves by writing a new
/// file and renaming it over the old one never touches the file being watched.
public final class FileWatcher {
    private let file: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?

    /// Creates the file's folder if it is missing, so there is something to watch.
    public init(file: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.file = file
        self.queue = queue
        self.onChange = onChange
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folderSource = makeSource(path: folder.path, events: [.write, .rename, .delete])
        watchFile()
    }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    private func fired() {
        watchFile()  // the file may be a new one now; watch whichever is there
        onChange()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: file.path, events: [.write, .extend, .rename, .delete])
    }

    private func makeSource(
        path: String, events: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in self?.fired() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
