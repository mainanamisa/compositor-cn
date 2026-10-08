import SwiftUI

/// The Remove tool's first-use sheet: asks before downloading the LaMa model (about 200 MB,
/// downloaded once into Application Support), then shows progress, and offers a retry on failure.
struct RemoveModelSheet: View {
    let store: RemoveModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("下载移除模型").font(.title2.bold())
            switch store.stage {
            case .confirm, nil:
                Text("首次使用移除工具需要下载 AI 修复模型（约 200 MB，只需下载一次）。模型在设备本地运行，不会上传你的图像。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { store.cancel() }.keyboardShortcut(.cancelAction)
                    Button("下载") { store.download() }.keyboardShortcut(.defaultAction)
                }
            case .downloading(let progress):
                Text("正在下载移除模型…").foregroundStyle(.secondary)
                ProgressView(value: progress)
                HStack {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("取消") { store.cancel() }.keyboardShortcut(.cancelAction)
                }
            case .unpacking:
                Text("正在解压模型…").foregroundStyle(.secondary)
                ProgressView()
                HStack {
                    Spacer()
                    Button("取消") { store.cancel() }.keyboardShortcut(.cancelAction)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button("取消") { store.cancel() }.keyboardShortcut(.cancelAction)
                    Button("重试") { store.download() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .roundedControls()
        // Clicking outside must not drop an in-flight download; confirm and failed may dismiss.
        .interactiveDismissDisabled(store.stage.map { stage in
            if case .downloading = stage { return true }
            return stage == .unpacking
        } ?? false)
    }
}
