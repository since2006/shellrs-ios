import ShellRSCore
import SwiftUI

/// The group form: a new group, or a group's name and place.
struct GroupEditor: View {
    enum Subject: Identifiable {
        /// In the group given, or at the top.
        case new(parent: UInt64?)
        case edit(HostGroup)

        var id: String {
            switch self {
            case .new(let parent): "new-\(parent.map(String.init) ?? "top")"
            case .edit(let group): "group-\(group.id)"
            }
        }

        var group: HostGroup? {
            if case .edit(let group) = self {
                return group
            }
            return nil
        }
    }

    let subject: Subject

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent: UInt64?
    @State private var problem: String?

    init(subject: Subject) {
        self.subject = subject
        switch subject {
        case .new(let parent):
            _parent = State(initialValue: parent)
        case .edit(let group):
            _name = State(initialValue: group.name)
            _parent = State(initialValue: group.parent)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledTextField("名称", text: $name, prompt: Text("例如 生产"))
                Picker("上级分组", selection: $parent) {
                    Text("（顶层）").tag(UInt64?.none)
                    ForEach(
                        HostTree.groupOptions(model.hosts.groups, excluding: subject.group?.id)
                    ) { option in
                        Text(option.path).tag(Optional(option.id))
                    }
                }
            }
            .navigationTitle(
                subject.group == nil
                    ? String(localized: "新建分组") : String(localized: "重命名分组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        subject.group == nil
                            ? String(localized: "创建") : String(localized: "保存")) {
                        save()
                    }
                }
            }
            .alert(
                "无法保存", isPresented: Binding(
                    get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    private func save() {
        do {
            try model.hosts.saveGroup(
                id: subject.group?.id, draft: GroupDraft(name: name, parent: parent))
            dismiss()
        } catch {
            problem = Describe.store(error)
        }
    }
}
