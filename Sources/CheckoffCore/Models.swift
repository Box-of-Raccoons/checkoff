import Foundation

/// One task. Only top-level tasks have children: nesting is one level deep.
public struct TodoItem: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var due: DateOnly?
    public var children: [TodoItem]
    /// Non-task lines that followed this task in the file (notes, blank lines).
    /// The app does not show them; it writes them back so nothing is lost.
    public var extraLines: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        due: DateOnly? = nil,
        children: [TodoItem] = [],
        extraLines: [String] = []
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.due = due
        self.children = children
        self.extraLines = extraLines
    }
}

/// The whole task file: any lines before the first task, then the tasks.
public struct TodoDocument: Equatable {
    public var preamble: [String]
    public var items: [TodoItem]

    public init(preamble: [String] = [], items: [TodoItem] = []) {
        self.preamble = preamble
        self.items = items
    }
}

/// Where a dragged task should land.
public enum DropAction: Equatable {
    /// Just before the target, as its sibling.
    case before(UUID)
    /// Just after the target, as its sibling.
    case after(UUID)
    /// As the last child of the target, which must be a top-level task.
    case into(UUID)
    /// At the end of the top-level list.
    case end
}
