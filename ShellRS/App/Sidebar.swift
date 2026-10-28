import ShellRSCore
import SwiftUI

/// The sidebar of a wide window: the hosts or the credentials, as the
/// desktop's sidebar switches between its lists, and the settings below.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.sidebarList {
            case .hosts:
                HostList()
            case .credentials:
                CredentialList()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let attention = model.sync.attention {
                SyncBanner(attention: attention)
            }
        }
        .toolbar {
            // Along the bottom: the top has the list's own buttons, and no
            // room left beside them in English.
            ToolbarItemGroup(placement: .bottomBar) {
                Picker("列表", selection: $model.sidebarList) {
                    Text("主机").tag(SidebarList.hosts)
                    Text("凭据").tag(SidebarList.credentials)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Button {
                    model.showingSettings = true
                } label: {
                    Label("设置", systemImage: model.sync.attention == nil ? "gear" : "gear.badge")
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
    }
}

/// What sync waits for the user to settle, where a narrow window would
/// alert: a wide one usually has a terminal open, typed into.
private struct SyncBanner: View {
    let attention: Attention
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(Describe.attention(attention))
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            Button("处理…") {
                model.reviewSync()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
