import CheckoffCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = ListUI()
    @AppStorage("hideDone") private var hideDone = false
    @State private var newTitle = ""
    @FocusState private var addFieldFocused: Bool

    private var visibleItems: [TodoItem] {
        hideDone ? model.document.items.filter { !$0.isDone } : model.document.items
    }

    private func visibleChildren(of item: TodoItem) -> [TodoItem] {
        hideDone ? item.children.filter { !$0.isDone } : item.children
    }

    var body: some View {
        VStack(spacing: 0) {
            addField
            Divider()
            if model.document.items.isEmpty {
                emptyState
            } else {
                taskList
            }
            if let message = model.errorMessage {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .environmentObject(ui)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $hideDone) {
                    Label("Hide Done Tasks", systemImage: hideDone ? "eye.slash" : "eye")
                }
                .help(hideDone ? "Show done tasks" : "Hide done tasks")
            }
        }
        .onChange(of: model.focusAddField) { addFieldFocused = true }
        .alert(
            "Mark \u{201C}\(ui.confirmCheck?.title ?? "")\u{201D} done?",
            isPresented: Binding(get: { ui.confirmCheck != nil }, set: { if !$0 { ui.confirmCheck = nil } }),
            presenting: ui.confirmCheck
        ) { item in
            Button("Mark Done") { model.change { $0.setDone(item.id, true) } }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            let open = item.children.filter { !$0.isDone }.count
            Text(open == 1
                ? "1 sub-task is still open. It will stay unchecked."
                : "\(open) sub-tasks are still open. They will stay unchecked.")
        }
        .alert(
            "Delete \u{201C}\(ui.confirmDelete?.title ?? "")\u{201D}?",
            isPresented: Binding(get: { ui.confirmDelete != nil }, set: { if !$0 { ui.confirmDelete = nil } }),
            presenting: ui.confirmDelete
        ) { item in
            Button("Delete", role: .destructive) { model.change { $0.delete(item.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.children.count == 1
                ? "Its 1 sub-task will be deleted too."
                : "Its \(item.children.count) sub-tasks will be deleted too.")
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFieldFocused)
                .onSubmit {
                    model.change { $0.add(title: newTitle) }
                    newTitle = ""
                    addFieldFocused = true
                }
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Nothing to do")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Type a task above and press Return.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleItems) { item in
                    let children = visibleChildren(of: item)
                    let open = !ui.isCollapsed(item)
                    TaskRow(item: item, parent: nil, showsChildren: open && !children.isEmpty)
                    if open {
                        ForEach(children) { child in
                            TaskRow(item: child, parent: item, showsChildren: false)
                        }
                    }
                    if ui.addingSubTaskTo == item.id {
                        SubTaskField(parent: item)
                    }
                }
                InsertionLine()
                    .padding(.leading, 8)
                    .opacity(ui.dropTarget == ListUI.DropTarget(row: nil, action: .end) ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        // Anywhere in the list that is not a row, including all the empty space
        // below the last task: dropping there moves a task to the end.
        .onDrop(of: [.text], delegate: TaskDropDelegate(target: nil, model: model, ui: ui))
    }
}

/// The inline field for typing sub-tasks one after another under a parent.
struct SubTaskField: View {
    let parent: TodoItem
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: ListUI
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField("Add a sub-task, Return to add another, Esc to finish", text: $title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return close() }
                    model.change { $0.add(title: title, toParent: parent.id) }
                    title = ""
                    focused = true
                }
                .onExitCommand(perform: close)
        }
        .padding(.leading, TaskRow.childIndent)
        .padding(.trailing, 10)
        .frame(minHeight: TaskRow.minHeight)
        .onAppear { focused = true }
    }

    private func close() {
        ui.addingSubTaskTo = nil
    }
}

struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
    }
}

/// Drag and drop for one row, or for the space below the list when `target` is nil.
struct TaskDropDelegate: DropDelegate {
    let target: TodoItem?
    var showsChildren = false
    var rowHeight: CGFloat = 1
    let model: AppModel
    let ui: ListUI

    private func action(_ info: DropInfo) -> DropAction? {
        guard let dragged = ui.draggingID else { return nil }
        guard let target else {
            return model.document.canApply(.end, to: dragged) ? .end : nil
        }
        return DropResolver.resolve(
            dragged: dragged, target: target.id,
            fraction: Double(info.location.y / max(rowHeight, 1)),
            targetShowsChildren: showsChildren, in: model.document)
    }

    private func show(_ info: DropInfo) {
        let next = action(info).map { ListUI.DropTarget(row: target?.id, action: $0) }
        if ui.dropTarget != next { ui.dropTarget = next }
    }

    func validateDrop(info: DropInfo) -> Bool {
        ui.draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        show(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        show(info)
        return DropProposal(operation: action(info) == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        if ui.dropTarget?.row == target?.id { ui.dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            ui.dropTarget = nil
            ui.draggingID = nil
        }
        guard let dragged = ui.draggingID, let action = action(info),
              let provider = info.itemProviders(for: [.text]).first
        else { return false }

        // The drag carries the task's id as text. Check it, so text dragged in from
        // another app can never move whichever task was dragged last.
        _ = provider.loadObject(ofClass: NSString.self) { [model] text, _ in
            guard (text as? String) == dragged.uuidString else { return }
            DispatchQueue.main.async {
                model.change { $0.apply(action, to: dragged) }
            }
        }
        return true
    }
}
