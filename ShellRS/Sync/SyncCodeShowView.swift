import CoreImage
import CoreImage.CIFilterBuiltins
import ShellRSCore
import SwiftUI

/// 同步配置码: this sync's setup code as a QR code another device scans,
/// and as text to copy or share. The code holds where sync goes and the
/// login to it, sealed with the sync password, which the other device
/// asks for.
struct SyncCodeShowView: View {
    let sync: SyncModel
    let close: () -> Void

    /// What the page shows.
    enum Shown {
        /// The code is being made: the place is read once for it.
        case making
        case made(String)
        case failed(String)
    }

    @State private var shown: Shown
    @State private var copied = false

    /// `shown` is what the page starts with: a code made already is shown
    /// as it is, without the place being read for another.
    init(sync: SyncModel, shown: Shown = .making, close: @escaping () -> Void) {
        self.sync = sync
        self.close = close
        _shown = State(initialValue: shown)
    }

    var body: some View {
        Form {
            switch shown {
            case .making:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在生成配置码…")
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let reason):
                Section {
                    Label {
                        Text("未能生成配置码：\(reason)")
                    } icon: {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    Button("重试") {
                        Task { await make() }
                    }
                }
            case .made(let code):
                made(code)
            }
        }
        .navigationTitle("同步配置码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    close()
                }
            }
        }
        .task {
            if case .making = shown {
                await make()
            }
        }
    }

    @ViewBuilder
    private func made(_ code: String) -> some View {
        Section {
            if let image = QRCode.image(of: code) {
                QRCodeView(image: image)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel(Text("配置码的二维码"))
            }
        } footer: {
            Text("在另一台设备上扫描这个二维码，或者粘贴配置码，再输入同步密码。")
        }
        Section {
            Text(verbatim: code)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Button(
                copied ? String(localized: "已复制配置码") : String(localized: "复制配置码"),
                systemImage: "doc.on.doc"
            ) {
                UIPasteboard.general.string = code
                copied = true
            }
            ShareLink(item: code) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        } footer: {
            Label("配置码里有同步位置的地址和登录密钥，已用同步密码加密。不要发到公开的地方。", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func make() async {
        shown = .making
        copied = false
        do {
            shown = .made(try await sync.setupCode())
        } catch {
            shown = .failed(Describe.sync(error))
        }
    }
}

/// A QR code on white with the blank border a reader needs, in every
/// appearance: the colors are the data a camera reads.
private struct QRCodeView: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 300)
    }
}

/// Text as a QR code.
enum QRCode {
    /// The code of `text`, a pixel to a module, to be scaled without
    /// smoothing; `nil` for more than a code holds.
    static func image(of text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // On a screen nothing wears a code off: the default level keeps
        // the modules of a long code large enough to read.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let rendered = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }
        return UIImage(cgImage: rendered)
    }
}
