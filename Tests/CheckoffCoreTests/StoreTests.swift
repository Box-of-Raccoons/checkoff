import Foundation
import Testing
@testable import CheckoffCore

/// Every store test works in its own temporary folder, never the real tasks file.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkoff-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var file: URL { url.appendingPathComponent("tasks.md") }

    func write(_ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func read() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}

@Suite struct StoreTests {
    @Test func aMissingFileIsAnEmptyList() throws {
        let folder = try TempFolder()
        let store = TodoStore(url: folder.file)
        try store.reload()
        #expect(store.document.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.file.path))
    }

    @Test func loadsAnExistingFile() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Ticket\n  - [x] Step 1\n")
        let store = TodoStore(url: folder.file)
        #expect(try store.reload())
        #expect(Fixture.shape(of: store.document) == "Ticket[Step 1]")
    }

    @Test func aChangeIsWrittenToTheFile() throws {
        let folder = try TempFolder()
        let store = TodoStore(url: folder.file)
        try store.mutate { $0.add(title: "Milk") }
        #expect(try folder.read() == "- [ ] Milk\n")
        try store.mutate { doc in
            if let id = doc.items.first?.id { doc.setDone(id, true) }
        }
        #expect(try folder.read() == "- [x] Milk\n")
    }

    @Test func createsTheFolderWhenItIsMissing() throws {
        let folder = try TempFolder()
        let nested = folder.url.appendingPathComponent("a/b/tasks.md")
        let store = TodoStore(url: nested)
        try store.mutate { $0.add(title: "Milk") }
        #expect(try String(contentsOf: nested, encoding: .utf8) == "- [ ] Milk\n")
    }

    @Test func picksUpAnEditMadeOutsideTheApp() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        try folder.write("- [x] Milk\n- [ ] Bread\n")
        #expect(try store.reload())
        #expect(store.document.items.map(\.title) == ["Milk", "Bread"])
        #expect(store.document.items.map(\.isDone) == [true, false])
    }

    @Test func reloadReportsNoChangeWhenTheFileIsTheSame() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let store = TodoStore(url: folder.file)
        #expect(try store.reload())
        #expect(try !store.reload())
        try store.mutate { $0.add(title: "Bread") }
        #expect(try !store.reload())  // our own write is not an outside edit
    }

    @Test func aChangeMadeRightAfterAnOutsideEditKeepsBoth() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        let milk = try #require(store.document.items.first?.id)

        // Something else adds a task; the app has not reloaded yet.
        try folder.write("- [ ] Milk\n- [ ] Bread\n")
        try store.mutate { $0.setDone(milk, true) }

        #expect(try folder.read() == "- [x] Milk\n- [ ] Bread\n")
    }

    @Test func tasksKeepTheirIdentityAcrossAReload() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Ticket\n  - [ ] Step 1\n  - [ ] Step 2\n- [ ] Milk\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        let ticket = try #require(store.document.items.first?.id)
        let step2 = try #require(store.document.items.first?.children.last?.id)
        let milk = try #require(store.document.items.last?.id)

        try folder.write("- [ ] New first\n- [ ] Ticket\n  - [ ] Step 1\n  - [x] Step 2\n- [ ] Milk\n")
        try store.reload()

        #expect(store.document.item(ticket)?.title == "Ticket")
        #expect(store.document.item(step2)?.title == "Step 2")
        #expect(store.document.item(step2)?.isDone == true)
        #expect(store.document.item(milk)?.title == "Milk")
    }

    @Test func twoTasksWithTheSameTitleStayDistinct() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Call\n- [ ] Call\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        let first = try #require(store.document.items.first?.id)
        let second = try #require(store.document.items.last?.id)
        #expect(first != second)

        try folder.write("- [ ] Call\n- [x] Call\n")
        try store.reload()
        #expect(store.document.items.map(\.id) == [first, second])
        #expect(Set(store.document.items.map(\.id)).count == 2)
    }

    @Test func aFileThatDisappearsBecomesAnEmptyList() throws {
        let folder = try TempFolder()
        try folder.write("- [ ] Milk\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        try FileManager.default.removeItem(at: folder.file)
        #expect(try store.reload())
        #expect(store.document.items.isEmpty)
    }

    @Test func aChangeThatDoesNothingDoesNotTouchTheFile() throws {
        let folder = try TempFolder()
        try folder.write("* [ ] Milk\n")  // not the canonical form
        let store = TodoStore(url: folder.file)
        try store.reload()
        try store.mutate { $0.setDone(UUID(), true) }
        #expect(try folder.read() == "* [ ] Milk\n")
    }

    @Test func notesInTheFileSurviveAChangeFromTheApp() throws {
        let folder = try TempFolder()
        try folder.write("# Work\n\n- [ ] Ticket\n  see the stack trace\n  - [ ] Step 1\n")
        let store = TodoStore(url: folder.file)
        try store.reload()
        let step = try #require(store.document.items.first?.children.first?.id)
        try store.mutate { $0.setDone(step, true) }
        #expect(try folder.read() == "# Work\n\n- [ ] Ticket\n  see the stack trace\n  - [x] Step 1\n")
    }
}
