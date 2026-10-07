import SwiftUI

/// The Crop tool's header. A view of its own because dragging the crop frame changes `cropRect` on
/// every mouse move: read here, only this bar re-renders, not the whole editor and its Layers panel.
struct CropControls: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: 14) {
            Text("裁剪").font(ToolHeaderStyle.titleFont)
            Picker("比例", selection: $session.cropRatioChoice) {
                // The tag stays English: EditorSession matches on it ("Free", "Original") when applying the ratio.
                ForEach([("Free", "自由"), ("Original", "原始比例"), ("1:1", "1:1"), ("4:3", "4:3"), ("3:4", "3:4"), ("16:9", "16:9"), ("9:16", "9:16")], id: \.0) { choice in
                    Text(choice.1).tag(choice.0)
                }
            }.frame(width: 170)
                .onChange(of: session.cropRatioChoice) { _, _ in session.changeCropRatio() }
            if let rect = session.cropRect {
                Text("\(Int(rect.width)) × \(Int(rect.height)) px").monospacedDigit()
            }
            Spacer()
            Button("取消") { session.cancelCrop() }.disabled(session.cropRect == nil)
            Button("应用裁剪") { Task { await session.commitCrop() } }
                .disabled(session.cropRect == nil)
        }.padding(.horizontal, 18).toolHeaderBar().disabled(session.showsBusy || session.document == nil)
    }
}
