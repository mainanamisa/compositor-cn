import SwiftUI

/// The Crop tool's header. A view of its own because dragging the crop frame changes `cropRect` on
/// every mouse move: read here, only this bar re-renders, not the whole editor and its Layers panel.
struct CropControls: View {
    @Bindable var session: EditorSession
    @State private var showsCustomRatio = false
    @State private var customRatio = "4:5"
    private let ratioGroups = [["Free", "Canvas"], ["1:1"], ["4:3", "16:9", "2.39:1"], ["3:4", "9:16"]]
    private var ratios: [String] { ratioGroups.flatMap { $0 } }

    var body: some View {
        HStack(spacing: 14) {
            Text("裁剪").font(ToolHeaderStyle.titleFont)
            Picker("比例", selection: ratioSelection) {
                // Grouped by shape: free and the canvas's own proportions, square, wide, tall.
                // The tags stay English: EditorSession matches on them ("Free", "Canvas") when applying the ratio.
                ForEach(ratioGroups.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    ForEach(ratioGroups[index], id: \.self) { choice in
                        Text(choice == "Free" ? "自由" : choice == "Canvas" ? "画布" : choice).tag(choice)
                    }
                }
                if !ratios.contains(session.cropRatioChoice) {
                    Text(session.cropRatioChoice).tag(session.cropRatioChoice)
                }
                Divider()
                Text("自定义…").tag("Custom")
            }.frame(width: 170)
                .popover(isPresented: $showsCustomRatio) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自定义比例").font(.headline)
                        TextField("宽:高", text: $customRatio)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { applyCustomRatio() }
                        Text("宽:高，例如 4:5 或 3:2")
                            .font(.caption).foregroundStyle(.secondary)
                        if CropGeometry.ratio(customRatio) == nil {
                            Text("请输入在文档尺寸限制内的正比例。")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("取消") { showsCustomRatio = false }
                            Spacer()
                            Button("应用") { applyCustomRatio() }
                                .disabled(CropGeometry.ratio(customRatio) == nil)
                        }
                    }.padding(16).frame(width: 280)
                }
            if let rect = session.cropRect {
                Text("\(Int(rect.width)) × \(Int(rect.height)) px").monospacedDigit()
            }
            Spacer()
            Button("取消") { session.cancelCrop() }.disabled(session.cropRect == nil)
            Button("应用裁剪") { Task { await session.commitCrop() } }
                .disabled(session.cropRect == nil)
        }.padding(.horizontal, 18).toolHeaderBar().disabled(session.showsBusy || session.document == nil)
    }

    private var ratioSelection: Binding<String> {
        Binding(get: { session.cropRatioChoice }, set: { choice in
            if choice == "Custom" {
                if CropGeometry.ratio(session.cropRatioChoice) != nil { customRatio = session.cropRatioChoice }
                showsCustomRatio = true
            } else {
                session.cropRatioChoice = choice
                session.changeCropRatio()
            }
        })
    }

    private func applyCustomRatio() {
        guard CropGeometry.ratio(customRatio) != nil else { return }
        session.cropRatioChoice = customRatio.split(separator: ":").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        }.joined(separator: ":")
        session.changeCropRatio()
        showsCustomRatio = false
    }
}
