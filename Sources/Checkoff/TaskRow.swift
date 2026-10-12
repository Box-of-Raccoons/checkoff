import CheckoffCore
import SwiftUI

struct TaskRow: View {
    static let minHeight: CGFloat = 30
    static let childIndent: CGFloat = 36

    let item: TodoItem
    /// The task this one sits under; nil for a top-level task.
    let parent: TodoItem?
    /// This is a parent and its sub-tasks are showing below it.
    let showsChildren: Bool

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: ListUI
    @State private var hovering = false
    @State private var height: CGFloat = TaskRow.minHeight

    private var isChild: Bool { parent != nil }

    private var dropAction: DropAction? {
        ui.dropTarget?.row == item.id ? ui.dropTarget?.action : nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if !isChild { disclosure }
            checkbox
            title
            Spacer(minLength: 8)
            if !item.children.isEmpty {
                Text("\(item.children.filter(\.isDone).count)/\(item.children.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Sub-tasks done")
            }
            if !isChild { addSubTaskButton }
            dueButton
        }
        .padding(.leading, isChild ? TaskRow.childIndent : 6)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(minHeight: TaskRow.minHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(background))
        .overlay(alignment: .top) {
            if case .before? = dropAction { insertionLine }
        }
        .overlay(alignment: .bottom) {
            if case .after? = dropAction { insertionLine }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onDrag {
            ui.draggingID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: TaskDropDelegate(
            target: item, showsChildren: showsChildren, rowHeight: height, model: model, ui: ui))
        .contextMenu { menu }
    }

    private var background: Color {
        if case .into? = dropAction { return Color.accentColor.opacity(0.2) }
        return hovering ? Color.primary.opacity(0.06) : .clear
    }

    private var insertionLine: some View {
        InsertionLine().padding(.leading, isChild ? TaskRow.childIndent : 6)
    }

    // MARK: Pieces

    private var disclosure: some View {
        Button {
            ui.setCollapsed(item, !ui.isCollapsed(item), in: model.document)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(ui.isCollapsed(item) ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.children.isEmpty ? 0 : 1)
        .disabled(item.children.isEmpty)
        .help(ui.isCollapsed(item) ? "Show sub-tasks" : "Hide sub-tasks")
    }

    private var checkbox: some View {
        Button(action: toggleDone) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: isChild ? 14 : 16))
                .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
    }

    @ViewBuilder private var title: some View {
        if ui.editingID == item.id {
            TitleEditor(initial: item.title) { text in
                if let text { model.change { $0.setTitle(item.id, text) } }
                ui.editingID = nil
            }
        } else {
            Text(item.title)
                .font(isChild ? .body : .body.weight(.medium))
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(3)
                .onTapGesture(count: 2) { ui.editingID = item.id }
        }
    }

    private var addSubTaskButton: some View {
        Button(action: startSubTask) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0)
        .help("Add a sub-task")
    }

    private var dueButton: some View {
        let showing = Binding(
            get: { ui.duePickerFor == item.id },
            set: { if !$0, ui.duePickerFor == item.id { ui.duePickerFor = nil } })

        return Button {
            ui.duePickerFor = item.id
        } label: {
            if let due = item.due {
                let overdue = !item.isDone && DueFormatting.isOverdue(due, today: model.today)
                Text(DueFormatting.label(for: due, today: model.today))
                    .font(.callout)
                    .foregroundStyle(overdue ? Color.red : Color.secondary)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .opacity(hovering || showing.wrappedValue ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 18, minHeight: 20)
        .contentShape(Rectangle())
        .help(item.due == nil ? "Set a due date" : "Change the due date")
        .popover(isPresented: showing, arrowEdge: .bottom) {
            DuePicker(item: item)
        }
    }

    @ViewBuilder private var menu: some View {
        if !isChild {
            Button("Add Sub-task", action: startSubTask)
        }
        Button("Rename") { ui.editingID = item.id }
        Divider()
        Button("Due Today") { setDue(model.today) }
        Button("Due Tomorrow") { setDue(DateOnly(tomorrow)) }
        Button("Choose Due Date\u{2026}") { ui.duePickerFor = item.id }
        if item.due != nil {
            Button("Clear Due Date") { setDue(nil) }
        }
        Divider()
        if let parent {
            Button("Move to Top Level") { model.change { $0.apply(.after(parent.id), to: item.id) } }
        }
        if item.children.isEmpty {
            let others = model.document.items.filter { $0.id != item.id && $0.id != parent?.id }
            if !others.isEmpty {
                Menu("Move Under") {
                    ForEach(others) { other in
                        Button(other.title) { model.change { $0.apply(.into(other.id), to: item.id) } }
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive, action: delete)
    }

    // MARK: Actions

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: model.today.date()) ?? Date()
    }

    private func toggleDone() {
        // Checking a parent never checks its sub-tasks, so say so before leaving some open.
        if !item.isDone, item.children.contains(where: { !$0.isDone }) {
            ui.confirmCheck = item
        } else {
            model.change { $0.setDone(item.id, !item.isDone) }
        }
    }

    private func startSubTask() {
        ui.setCollapsed(item, false, in: model.document)
        ui.addingSubTaskTo = item.id
    }

    private func setDue(_ due: DateOnly?) {
        model.change { $0.setDue(item.id, due) }
    }

    private func delete() {
        if item.children.isEmpty {
            model.change { $0.delete(item.id) }
        } else {
            ui.confirmDelete = item
        }
    }
}

/// The title as an editable field. Return or clicking away saves; Esc cancels.
struct TitleEditor: View {
    let initial: String
    /// Called once with the new title, or nil when the edit was cancelled.
    let finish: (String?) -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { end(text) }
            .onExitCommand { end(nil) }
            .onChange(of: focused) { if !focused { end(text) } }
            .onAppear {
                text = initial
                focused = true
            }
    }

    private func end(_ result: String?) {
        guard !finished else { return }
        finished = true
        finish(result)
    }
}

/// The small calendar that sets or clears a task's due date.
struct DuePicker: View {
    let item: TodoItem
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: ListUI

    var body: some View {
        let date = Binding<Date>(
            get: { (item.due ?? model.today).date() },
            set: { picked in set(DateOnly(picked)) })

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Today") { set(model.today) }
                Button("Tomorrow") {
                    let next = Calendar.current.date(byAdding: .day, value: 1, to: model.today.date())
                    set(DateOnly(next ?? Date()))
                }
                Spacer()
                if item.due != nil {
                    Button("No Date") {
                        set(nil)
                        ui.duePickerFor = nil
                    }
                }
            }
            DatePicker("Due date", selection: date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        .padding(12)
        .frame(width: 250)
    }

    private func set(_ due: DateOnly?) {
        model.change { $0.setDue(item.id, due) }
    }
}
