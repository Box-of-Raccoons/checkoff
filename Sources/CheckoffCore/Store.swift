import Foundation

/// Keeps a `TodoDocument` in step with the task file on disk.
///
/// Other programs may edit the file at any time, so every change first reads
/// the file again and is then applied to what is there now.
public final class TodoStore {
    public let url: URL
    public private(set) var document = TodoDocument()
    /// The file's text as of the last read or write; nil when there is no file.
    private var lastText: String?

    public init(url: URL) {
        self.url = url
    }

    /// Reads the file if it changed since the last read or write.
    /// - Returns: true when the document was replaced.
    @discardableResult
    public func reload() throws -> Bool {
        let text = try readFile()
        guard text != lastText else { return false }
        var fresh = TodoMarkdown.parse(text ?? "")
        fresh.adoptIDs(from: document)
        document = fresh
        lastText = text
        return true
    }

    /// Applies a change and writes the file. A change that alters nothing leaves the file untouched.
    public func mutate(_ body: (inout TodoDocument) -> Void) throws {
        try reload()
        var changed = document
        body(&changed)
        guard changed != document else { return }

        let text = TodoMarkdown.serialize(changed)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        document = changed
        lastText = text
    }

    private func readFile() throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
