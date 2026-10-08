import SwiftUI

/// The app's Settings window (⌘,). Right now it only holds the undo history's memory budget;
/// more preferences can join the Form as they appear.
struct PreferencesView: View {
    @AppStorage("historyRetainedMB") private var historyRetainedMB = 1024

    var body: some View {
        Form {
            Picker("撤销历史内存上限：", selection: $historyRetainedMB) {
                Text("256 MB").tag(256)
                Text("512 MB").tag(512)
                Text("1 GB（推荐）").tag(1024)
                Text("2 GB").tag(2048)
                Text("4 GB").tag(4096)
            }
            Text("撤销历史最多记录 100 步；历史占用的内存超过上限时，最旧的记录会被丢弃。图像越大，每步占的内存越多。修改即时生效。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
