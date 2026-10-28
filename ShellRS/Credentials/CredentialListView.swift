import ShellRSCore
import SwiftUI
import UIKit

/// The 凭据 tab of a narrow window: the list in a stack of its own.
struct CredentialListView: View {
    var body: some View {
        NavigationStack {
            CredentialList()
        }
    }
}

/// The saved credentials, a username with a password or a private key that
/// several hosts share: tap one to edit it. Its container gives it the
/// navigation bar: the 凭据 tab or the sidebar.
struct CredentialList: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var editing: CredentialEditor.Subject?
    @State private var deleting: Credential?
    @State private var failure: String?

    var body: some View {
        @Bindable var hosts = model.hosts
        let shown = hosts.credentials.filter { $0.matches(query) }
        List {
            ForEach(shown, id: \.id) { credential in
                Button {
                    editing = .edit(credential)
                } label: {
                    CredentialRow(credential: credential, hosts: users(of: credential))
                }
                .tint(.primary)
                .swipeActions {
                    Button("删除", role: .destructive) {
                        deleting = credential
                    }
                }
                .contextMenu {
                    Button("编辑凭据…", systemImage: "pencil") {
                        editing = .edit(credential)
                    }
                    if credential.kind == .key {
                        Button("复制公钥", systemImage: "doc.on.doc") {
                            Task { await copyPublicKey(of: credential) }
                        }
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) {
                        deleting = credential
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索凭据")
        .overlay {
            if hosts.credentials.isEmpty {
                ContentUnavailableView {
                    Label("还没有凭据", systemImage: "key")
                } description: {
                    Text("保存一套用户名和密码或私钥，让多台主机共用。")
                } actions: {
                    Button("新建凭据") {
                        editing = .new(generate: false)
                    }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("凭据")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建凭据…", systemImage: "key") {
                        editing = .new(generate: false)
                    }
                    Button("生成密钥…", systemImage: "wand.and.stars") {
                        editing = .new(generate: true)
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { subject in
            CredentialEditor(subject: subject)
        }
        .confirmation(
            Text(verbatim: deleting.map { String(localized: "删除“\($0.name)”？") } ?? ""),
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { credential in
            Button("删除", role: .destructive) {
                do {
                    try hosts.delete(credential)
                } catch {
                    failure = Describe.store(error)
                }
            }
        } message: { credential in
            if let message = Describe.deleting(credential, usedBy: users(of: credential)) {
                Text(message)
            }
        }
        .alert(
            "出错了", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    /// How many hosts log in with `credential`.
    private func users(of credential: Credential) -> Int {
        model.hosts.hostsUsing(credential).count
    }

    private func copyPublicKey(of credential: Credential) async {
        if let key = await model.hosts.store.publicKey(credential: credential.id) {
            UIPasteboard.general.string = key
        } else {
            failure = String(localized: "这把私钥要口令才能读出公钥")
        }
    }
}

private struct CredentialRow: View {
    let credential: Credential
    /// How many hosts use it.
    let hosts: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: credential.kind.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.name)
                    .lineLimit(1)
                Text(hosts == 0 ? credential.summary : String(localized: "\(credential.summary) · \(hosts) 台主机"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

extension Credential {
    /// Whether what was typed in the search field finds it: in its name,
    /// user or kind, ignoring case, as on the desktop.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty
            || [name, user, kind.label].contains { $0.lowercased().contains(query) }
    }
}

extension CredentialKind {
    var symbol: String {
        switch self {
        case .password: "ellipsis.rectangle"
        case .key: "key"
        case .agent: "person.badge.key"
        }
    }
}
