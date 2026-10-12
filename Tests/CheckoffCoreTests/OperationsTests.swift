import Foundation
import Testing
@testable import CheckoffCore

/// A ticket with three steps, then two loose tasks.
///
///     - [ ] Ticket
///       - [x] Step 1
///       - [ ] Step 2
///       - [ ] Step 3
///     - [ ] Milk
///     - [ ] Bread
final class Fixture {
    var doc: TodoDocument
    let ticket = UUID(), step1 = UUID(), step2 = UUID(), step3 = UUID(), milk = UUID(), bread = UUID()

    init() {
        doc = TodoDocument()
        doc.items = [
            TodoItem(id: ticket, title: "Ticket", children: [
                TodoItem(id: step1, title: "Step 1", isDone: true),
                TodoItem(id: step2, title: "Step 2"),
                TodoItem(id: step3, title: "Step 3"),
            ]),
            TodoItem(id: milk, title: "Milk"),
            TodoItem(id: bread, title: "Bread"),
        ]
    }

    // Forwarders: #expect cannot call a mutating method on a struct directly.
    @discardableResult func add(title: String, toParent parent: UUID? = nil) -> UUID? {
        doc.add(title: title, toParent: parent)
    }
    @discardableResult func setDone(_ id: UUID, _ done: Bool) -> Bool { doc.setDone(id, done) }
    @discardableResult func setTitle(_ id: UUID, _ title: String) -> Bool { doc.setTitle(id, title) }
    @discardableResult func setDue(_ id: UUID, _ due: DateOnly?) -> Bool { doc.setDue(id, due) }
    @discardableResult func delete(_ id: UUID) -> Bool { doc.delete(id) }
    @discardableResult func apply(_ action: DropAction, to id: UUID) -> Bool { doc.apply(action, to: id) }

    /// The shape as text, so a test reads as one line: "Ticket[Step 1,Step 2] Milk".
    var shape: String { Fixture.shape(of: doc) }

    static func shape(of doc: TodoDocument) -> String {
        doc.items.map { item in
            item.children.isEmpty
                ? item.title
                : "\(item.title)[\(item.children.map(\.title).joined(separator: ","))]"
        }.joined(separator: " ")
    }
}

@Suite struct OperationsTests {
    @Test func addsATaskAtTheEndOfTheList() throws {
        let f = Fixture()
        let id = try #require(f.add(title: "Eggs"))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk Bread Eggs")
        #expect(f.doc.item(id)?.title == "Eggs")
        #expect(f.doc.item(id)?.isDone == false)
        #expect(f.doc.item(id)?.due == nil)
    }

    @Test func addsASubTaskAtTheEndOfItsParent() throws {
        let f = Fixture()
        let id = try #require(f.add(title: "Step 4", toParent: f.ticket))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3,Step 4] Milk Bread")
        #expect(f.doc.parentID(of: id) == f.ticket)
    }

    @Test func aChildlessTaskCanTakeItsFirstSubTask() {
        let f = Fixture()
        #expect(f.add(title: "Whole", toParent: f.milk) != nil)
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk[Whole] Bread")
    }

    @Test func refusesASubTaskUnderASubTask() {
        let f = Fixture()
        #expect(f.add(title: "Too deep", toParent: f.step2) == nil)
        #expect(f.add(title: "Nowhere", toParent: UUID()) == nil)
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk Bread")
    }

    @Test func refusesABlankTitle() {
        let f = Fixture()
        #expect(f.add(title: "") == nil)
        #expect(f.add(title: "   \n ") == nil)
        #expect(f.doc.items.count == 3)
    }

    @Test func tidiesTheTitleAndPullsOutATypedDueDate() throws {
        let f = Fixture()
        let id = try #require(f.add(title: "  Call the\nbank @due(2026-10-20) "))
        #expect(f.doc.item(id)?.title == "Call the bank")
        #expect(try f.doc.item(id)?.due == day("2026-10-20"))
    }

    @Test func findsItemsAndTheirParents() {
        let f = Fixture()
        #expect(f.doc.item(f.step2)?.title == "Step 2")
        #expect(f.doc.item(f.milk)?.title == "Milk")
        #expect(f.doc.item(UUID()) == nil)
        #expect(f.doc.parentID(of: f.step2) == f.ticket)
        #expect(f.doc.parentID(of: f.milk) == nil)
    }

    @Test func checkingASubTaskTouchesOnlyThatSubTask() {
        let f = Fixture()
        #expect(f.setDone(f.step2, true))
        #expect(f.doc.items[0].children.map(\.isDone) == [true, true, false])
        #expect(f.doc.items[0].isDone == false)
        #expect(f.setDone(f.step1, false))
        #expect(f.doc.items[0].children.map(\.isDone) == [false, true, false])
    }

    @Test func checkingAParentLeavesItsSubTasksAlone() {
        let f = Fixture()
        #expect(f.setDone(f.ticket, true))
        #expect(f.doc.items[0].isDone)
        #expect(f.doc.items[0].children.map(\.isDone) == [true, false, false])
    }

    @Test func checkingSomethingThatIsNotThereFails() {
        let f = Fixture()
        let before = f.doc
        #expect(!f.setDone(UUID(), true))
        #expect(f.doc == before)
    }

    @Test func countsOpenSubTasksAndProgress() {
        let f = Fixture()
        #expect(f.doc.openChildCount(of: f.ticket) == 2)
        #expect(f.doc.progress(of: f.ticket)?.done == 1)
        #expect(f.doc.progress(of: f.ticket)?.total == 3)
        f.setDone(f.step2, true)
        #expect(f.doc.openChildCount(of: f.ticket) == 1)
        #expect(f.doc.progress(of: f.ticket)?.done == 2)
        #expect(f.doc.openChildCount(of: f.milk) == 0)
        #expect(f.doc.progress(of: f.milk) == nil)  // no sub-tasks, nothing to count
    }

    @Test func setsAndClearsADueDate() throws {
        let f = Fixture()
        #expect(try f.setDue(f.step2, day("2026-10-15")))
        #expect(try f.doc.item(f.step2)?.due == day("2026-10-15"))
        #expect(try f.setDue(f.milk, day("2026-11-01")))
        #expect(try f.doc.item(f.milk)?.due == day("2026-11-01"))
        #expect(f.setDue(f.step2, nil))
        #expect(f.doc.item(f.step2)?.due == nil)
        #expect(try !f.setDue(UUID(), day("2026-10-15")))
    }

    @Test func renamesATask() {
        let f = Fixture()
        #expect(f.setTitle(f.step2, "  Step two "))
        #expect(f.doc.item(f.step2)?.title == "Step two")
        #expect(!f.setTitle(f.step2, "   "))
        #expect(f.doc.item(f.step2)?.title == "Step two")
        #expect(!f.setTitle(UUID(), "Ghost"))
    }

    @Test func renamingWithATypedDueDateSetsIt() throws {
        let f = Fixture()
        #expect(f.setTitle(f.milk, "Oat milk @due(2026-10-13)"))
        #expect(f.doc.item(f.milk)?.title == "Oat milk")
        #expect(try f.doc.item(f.milk)?.due == day("2026-10-13"))
    }

    @Test func renamingWithoutADueDateKeepsTheOldOne() throws {
        let f = Fixture()
        f.setDue(f.milk, try day("2026-10-13"))
        #expect(f.setTitle(f.milk, "Oat milk"))
        #expect(try f.doc.item(f.milk)?.due == day("2026-10-13"))
    }

    @Test func deletesASubTask() {
        let f = Fixture()
        #expect(f.delete(f.step2))
        #expect(f.shape == "Ticket[Step 1,Step 3] Milk Bread")
    }

    @Test func deletingAParentTakesItsSubTasksWithIt() {
        let f = Fixture()
        #expect(f.delete(f.ticket))
        #expect(f.shape == "Milk Bread")
        #expect(f.doc.item(f.step1) == nil)
    }

    @Test func deletingSomethingThatIsNotThereFails() {
        let f = Fixture()
        #expect(!f.delete(UUID()))
        #expect(f.shape == "Ticket[Step 1,Step 2,Step 3] Milk Bread")
    }
}
